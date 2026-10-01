import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/asset_model.dart';
import '../../models/request_model.dart';
import 'asset_service.dart';
import 'deployment_service.dart';
import 'guarded_transaction.dart';
import 'log_service.dart';
import 'permission_service.dart';

class RequestService {
  RequestService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const String _requestCollection = 'requests';
  static const String _assetCollection = 'assets';
  static const String _notificationCollection = 'notifications';
  static const String _userCollection = 'users';

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection(_requestCollection);

  CollectionReference<Map<String, dynamic>> get _assets =>
      _firestore.collection(_assetCollection);

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection(_notificationCollection);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(_userCollection);

  DeploymentService get _deploymentService =>
      DeploymentService(firestore: _firestore);

  /// The same service the direct (non-request) assign and unassign use, so
  /// an approval runs exactly the workflow the user was shown.
  AssetService get _assetService => AssetService(firestore: _firestore);

  /// Audit trail. Written only after a decision has committed, and never
  /// inside a transaction - see [LogService.recordActivity].
  LogService get _logService => LogService(firestore: _firestore, auth: _auth);

  // ============================================================
  // CURRENT USER / ROLE
  // ============================================================

  String get _currentUid => _auth.currentUser?.uid.trim() ?? '';

  /// The acting role, resolved the way firestore.rules resolves it.
  ///
  /// The rules read the primary `role` field alone, trimmed and lower-cased.
  /// This used to fold in the `roles` array as well, which could grant an
  /// account a role the rules would then refuse - the array is a mirror, so it
  /// must never decide anything. Returns '' for a stored value that is not one
  /// of the three canonical roles, and an unknown role gets nothing.
  Future<String> _getCurrentRole() async {
    final uid = _currentUid;

    if (uid.isEmpty) {
      throw Exception('You are not authenticated.');
    }

    final snapshot = await _users.doc(uid).get();

    if (!snapshot.exists || snapshot.data() == null) {
      throw Exception('Your user profile could not be found.');
    }

    return _canonicalRole(snapshot.data()!['role']);
  }

  /// Trim + lower-case of a stored role, or '' when it is not canonical.
  ///
  /// Delegates to PermissionService so an authorisation decision is never
  /// forked: `normalizeRole` is exactly `roleOf()` in firestore.rules (no
  /// alias mapping), and `isMainRole` keeps only the three canonical values.
  static String _canonicalRole(Object? value) {
    final role = PermissionService.normalizeRole(value?.toString());

    return PermissionService.isMainRole(role) ? role : '';
  }

  // ============================================================
  // GET REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getRequests() {
    final uid = _currentUid;

    if (uid.isEmpty) {
      return Stream.value(<RequestModel>[]);
    }

    return _getCurrentRoleForStream(uid);
  }

  /// The role lookup is wrapped in [Stream.fromFuture] rather than awaited in
  /// an `async*` body: when the listener is cancelled while the lookup is
  /// still pending (logout or account switch), a late failure (e.g.
  /// permission-denied for the signed-out account) is discarded together
  /// with the cancelled subscription instead of escaping as an uncaught
  /// error. While subscribed, failures still reach the listener's onError.
  Stream<List<RequestModel>> _getCurrentRoleForStream(String uid) {
    return Stream<String>.fromFuture(_getCurrentRole()).asyncExpand((role) {
      // An Admin may now decide a request about ANY inventory, exactly like a
      // Super Admin, so both read the whole collection. The previous Admin
      // query kept only requests addressed to them or about inventory they
      // own, which hid requests they are allowed - and expected - to answer.
      //
      // Unordered on purpose: an orderBy('requestDate') would drop a request
      // that has no date, and _mapRequestSnapshot already sorts by date.
      if (role == 'super_admin' || role == 'admin') {
        return _requests.snapshots().map(_mapRequestSnapshot);
      }

      if (role == 'user') {
        return _requests
            .where('requestedBy', isEqualTo: uid)
            .snapshots()
            .map(_mapRequestSnapshot);
      }

      // An unrecognised stored role gets nothing, the way the rules treat it.
      return Stream.value(<RequestModel>[]);
    });
  }

  List<RequestModel> _mapRequestSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final requests = snapshot.docs
        .map((doc) => RequestModel.fromMap(doc.data(), id: doc.id))
        .toList();

    requests.sort(
      (a, b) => (b.requestDate ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.requestDate ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );

    return requests;
  }

  // ============================================================
  // GET SINGLE REQUEST
  // ============================================================

  Future<RequestModel?> getRequestById(String id) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      return null;
    }

    final doc = await _requests.doc(cleanId).get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return RequestModel.fromMap(doc.data()!, id: doc.id);
  }

  // ============================================================
  // CREATE REQUEST
  // ============================================================

  Future<void> createRequest(RequestModel request) async {
    final uid = _currentUid;

    if (uid.isEmpty) {
      throw Exception('You are not authenticated.');
    }

    if (request.requestedBy.trim() != uid) {
      throw Exception('You can only create a request for yourself.');
    }

    final data = request.toMap();

    data.remove('id');

    data['requestedBy'] = uid;
    data['status'] = 'Pending';
    data['requestDate'] = FieldValue.serverTimestamp();
    data['approvedDate'] = null;
    data['approvedBy'] = '';
    data['adminRemarks'] = '';

    // ----------------------------------------------------------
    // ROUTING
    //
    // assetAdminId: owner of the inventory the request concerns.
    // receiverId:   when not supplied, a normal User's request is
    //               routed to the Admin that manages the User.
    // ----------------------------------------------------------

    final requesterProfile = await _users.doc(uid).get();
    final requesterData = requesterProfile.data() ?? const <String, dynamic>{};

    String assetAdminId = '';

    final assetId = request.assetId.trim();

    if (assetId.isNotEmpty) {
      final assetSnapshot = await _assets.doc(assetId).get();

      if (!assetSnapshot.exists || assetSnapshot.data() == null) {
        throw Exception('The selected asset no longer exists.');
      }

      assetAdminId = (assetSnapshot.data()!['adminId'] ?? '').toString().trim();
    }

    var receiverId = request.receiverId.trim();

    if (receiverId.isEmpty) {
      final role = (requesterData['role'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (role == 'user') {
        receiverId = (requesterData['createdBy'] ?? '').toString().trim();
      }
    }

    data['receiverId'] = receiverId;
    data['assetAdminId'] = assetAdminId;

    final requesterName = request.requestedUserName.trim().isNotEmpty
        ? request.requestedUserName.trim()
        : (requesterData['name'] ?? '').toString().trim();

    data['requestedUserName'] = requesterName;

    final routedRequest = request.copyWith(
      receiverId: receiverId,
      requestedUserName: requesterName,
    );

    // The request and its notifications are committed atomically, so a
    // failure can never leave a saved request that the UI reports as failed
    // (which previously led users to resubmit duplicates).
    final requestRef = _requests.doc();
    final batch = _firestore.batch();

    batch.set(requestRef, data);

    _addNotificationToBatch(
      batch,
      notificationId: '${requestRef.id}_created',
      userId: uid,
      title: _requestCreatedTitle(routedRequest),
      message: _requestCreatedMessage(routedRequest),
      type: 'request_created',
      requestId: requestRef.id,
    );

    if (receiverId.isNotEmpty && receiverId != uid) {
      _addNotificationToBatch(
        batch,
        notificationId: '${requestRef.id}_receiver_created',
        userId: receiverId,
        title: _receiverRequestTitle(routedRequest),
        message: _receiverRequestMessage(routedRequest),
        type: 'request_received',
        requestId: requestRef.id,
      );
    }

    await batch.commit();
  }

  // ============================================================
  // UPDATE REQUEST STATUS
  // ============================================================

  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    required String remarks,
    required String approvedBy,
  }) async {
    final cleanRequestId = requestId.trim();

    if (cleanRequestId.isEmpty) {
      throw Exception('Request ID is required.');
    }

    final currentUid = _currentUid;

    if (currentUid.isEmpty) {
      throw Exception('You are not authenticated.');
    }

    final currentRole = await _getCurrentRole();

    if (currentRole != 'super_admin' && currentRole != 'admin') {
      throw Exception('Only an Admin or Super Admin can decide a request.');
    }

    final request = await getRequestById(cleanRequestId);

    if (request == null) {
      throw Exception('Request not found.');
    }

    if (!request.isPending) {
      throw Exception('This request has already been processed.');
    }

    if (request.requestedBy.trim() == currentUid) {
      throw Exception('You cannot approve or reject your own request.');
    }

    // No owner check: canActOnRequest is isManager() in firestore.rules, so an
    // Admin decides requests about any inventory. The guards that remain are
    // the ones that still matter - the request must be Pending, nobody
    // approves their own, and a decided request is immutable (re-checked
    // inside every transaction below).

    final cleanStatus = status.trim();

    if (cleanStatus.isEmpty) {
      throw Exception('Request status is required.');
    }

    final normalizedStatus = cleanStatus.toLowerCase();

    if (normalizedStatus != 'approved' && normalizedStatus != 'rejected') {
      throw Exception('Only Approved or Rejected status is allowed.');
    }

    final requestRef = _requests.doc(cleanRequestId);

    final cleanApproverName = approvedBy.trim();

    if (cleanApproverName.isEmpty) {
      throw Exception('Approver name is required.');
    }

    await _applyRequestDecision(
      request: request,
      requestRef: requestRef,
      cleanRequestId: cleanRequestId,
      normalizedStatus: normalizedStatus,
      remarks: remarks,
      cleanApproverName: cleanApproverName,
      currentUid: currentUid,
    );

    // The audit entry is written only once the decision has committed. The
    // decision itself runs in a transaction that refuses a request which is no
    // longer Pending, and a failed log write is swallowed, so the trail can
    // never undo, retry or mis-report a decision the approver was already told
    // had succeeded.
    final approved = normalizedStatus == 'approved';

    await _logService.recordActivity(
      action: approved ? 'Request approved' : 'Request rejected',
      description:
          '${_requestTypeDisplay(request)} request for '
          '${_requestAssetName(request)} was '
          '${approved ? 'approved' : 'rejected'}.',
      module: 'Requests',
      targetId: cleanRequestId,
      userName: cleanApproverName,
    );
  }

  /// Applies an already-validated decision: one branch per request type, each
  /// committing the asset change and the request's own status together.
  ///
  /// Split out of [updateRequestStatus] purely so the audit entry above is
  /// written once, after whichever branch ran has committed, instead of being
  /// repeated at every early return in here.
  Future<void> _applyRequestDecision({
    required RequestModel request,
    required DocumentReference<Map<String, dynamic>> requestRef,
    required String cleanRequestId,
    required String normalizedStatus,
    required String remarks,
    required String cleanApproverName,
    required String currentUid,
  }) async {
    // ==========================================================
    // REJECT
    // ==========================================================

    if (normalizedStatus == 'rejected') {
      await runGuardedTransaction(_firestore, (transaction) async {
        await _ensurePendingInTransaction(transaction, requestRef);

        transaction.update(requestRef, {
          'status': 'Rejected',
          'adminRemarks': remarks.trim(),
          'approvedBy': cleanApproverName,
          'approvedByUid': currentUid,
          'approvedDate': FieldValue.serverTimestamp(),
        });
      });

      await _createStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Rejected',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      await _createReceiverStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Rejected',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      return;
    }

    // ==========================================================
    // APPROVE TRANSFER REQUEST
    // ==========================================================

    if (request.isTransferRequest) {
      await _approveTransferRequest(
        request: request,
        requestRef: requestRef,
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      return;
    }

    // ==========================================================
    // APPROVE EDIT REQUEST
    // ==========================================================

    if (request.isAssignmentRequest) {
      await _approveAssignmentRequest(
        request: request,
        requestRef: requestRef,
        remarks: remarks,
        approvedBy: cleanApproverName,
        assigneeId: request.assigneeId,
      );

      await _createStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      await _createReceiverStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      return;
    }

    // Filed before 'Assignment' existed, but unmistakably one of them. Only
    // a request whose ONLY difference is the holder is diverted; anything
    // else keeps ordinary Edit behaviour, so no existing edit changes meaning.
    final legacyHolder = _legacyAssignmentTarget(request);

    if (request.isEditRequest && legacyHolder != null) {
      await _approveAssignmentRequest(
        request: request,
        requestRef: requestRef,
        remarks: remarks,
        approvedBy: cleanApproverName,
        assigneeId: legacyHolder,
      );

      await _createStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      await _createReceiverStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      return;
    }

    if (request.isEditRequest) {
      await _approveEditRequest(
        request: request,
        requestRef: requestRef,
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      await _createStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      await _createReceiverStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      return;
    }

    // ==========================================================
    // APPROVE DELETE REQUEST
    // ==========================================================

    if (request.isDeleteRequest) {
      await _approveDeleteRequest(
        request: request,
        requestRef: requestRef,
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      await _createStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      await _createReceiverStatusNotification(
        request: request,
        requestId: cleanRequestId,
        status: 'Approved',
        remarks: remarks,
        approvedBy: cleanApproverName,
      );

      return;
    }

    // ==========================================================
    // OTHER REQUEST TYPES
    // ==========================================================

    await runGuardedTransaction(_firestore, (transaction) async {
      await _ensurePendingInTransaction(transaction, requestRef);

      transaction.update(requestRef, {
        'status': 'Approved',
        'adminRemarks': remarks.trim(),
        'approvedBy': cleanApproverName,
        'approvedByUid': currentUid,
        'approvedDate': FieldValue.serverTimestamp(),
      });
    });

    await _createStatusNotification(
      request: request,
      requestId: cleanRequestId,
      status: 'Approved',
      remarks: remarks,
      approvedBy: cleanApproverName,
    );

    await _createReceiverStatusNotification(
      request: request,
      requestId: cleanRequestId,
      status: 'Approved',
      remarks: remarks,
      approvedBy: cleanApproverName,
    );
  }

  // ============================================================
  // APPROVE REQUEST
  // ============================================================

  Future<void> approveRequest({
    required String requestId,
    required String approvedBy,
    String remarks = '',
  }) async {
    await updateRequestStatus(
      requestId: requestId,
      status: 'Approved',
      remarks: remarks,
      approvedBy: approvedBy,
    );
  }

  // ============================================================
  // REJECT REQUEST
  // ============================================================

  Future<void> rejectRequest({
    required String requestId,
    required String approvedBy,
    String remarks = '',
  }) async {
    await updateRequestStatus(
      requestId: requestId,
      status: 'Rejected',
      remarks: remarks,
      approvedBy: approvedBy,
    );
  }

  // ============================================================
  // APPROVE TRANSFER REQUEST
  // ============================================================

  Future<void> _approveTransferRequest({
    required RequestModel request,
    required DocumentReference<Map<String, dynamic>> requestRef,
    required String remarks,
    required String approvedBy,
  }) async {
    if (request.assetId.trim().isEmpty) {
      throw Exception('Asset ID is missing from the transfer request.');
    }

    if (!request.hasTransferData) {
      throw Exception(
        'Transfer information is incomplete. Destination and quantity are required.',
      );
    }

    final assetRef = _assets.doc(request.assetId.trim());

    final assetSnapshot = await assetRef.get();

    if (!assetSnapshot.exists || assetSnapshot.data() == null) {
      throw Exception('The requested asset no longer exists.');
    }

    final assetData = assetSnapshot.data()!;

    final asset = AssetModel.fromMap(assetData, assetSnapshot.id);

    final destinationId = request.destinationBazaarId.trim();

    final destinationName = request.destinationBazaarName.trim();

    if (destinationName.isEmpty) {
      throw Exception('Destination Bazaar name is missing.');
    }

    // Head Office is identified by an EMPTY id plus the name "Head Office" -
    // the convention DeploymentService.transferAsset and every direct
    // (non-request) transfer already use. Treating an empty id as "missing"
    // made a return to Head Office impossible to approve: the request stuck
    // on Pending for good, because the only destination it can ever have is
    // the one being rejected here.
    final toHeadOffice = _isHeadOffice(destinationName);

    if (destinationId.isEmpty && !toHeadOffice) {
      throw Exception('Destination Bazaar is missing.');
    }

    // transferAsset requires a NON-EMPTY destination id and keeps its own name
    // for Head Office, so letting the empty id through would only move the
    // refusal one call deeper. A request filed before the assistant knew that
    // is mapped onto the sentinel here, which is what makes an already-Pending
    // one approvable instead of stuck for good. Only an EMPTY id is mapped: a
    // request that names a real Bazaar keeps it.
    final resolvedDestinationId = destinationId.isEmpty && toHeadOffice
        ? DeploymentService.headOfficeId
        : destinationId;

    if (request.transferQuantity <= 0) {
      throw Exception('Transfer quantity must be greater than 0.');
    }

    final sourceId = request.sourceBazaarId.trim();

    final sourceName = request.sourceBazaarName.trim();

    final resolvedSourceName = sourceName.isNotEmpty
        ? sourceName
        : _resolveAssetLocation(asset);

    // The stock movement and the request status change are committed in ONE
    // transaction that re-checks the request is still Pending, so a double
    // tap or two approvers can never move stock twice.
    final movementId = await _deploymentService.transferAsset(
      assetDocumentId: assetSnapshot.id,
      sourceId: sourceId,
      sourceName: resolvedSourceName,
      destinationId: resolvedDestinationId,
      destinationName: destinationName,
      quantity: request.transferQuantity,
      transferredBy: _currentUid,
      transferredByName: approvedBy.trim(),
      receiverName: request.receiverName.trim(),
      receiverContact: request.receiverContact.trim(),
      reason: request.transferRemarks.trim().isEmpty
          ? 'Approved Asset Transfer'
          : request.transferRemarks.trim(),
      remarks: remarks.trim().isEmpty
          ? request.transferRemarks.trim()
          : remarks.trim(),
      approvalRequestRef: requestRef,
      approvalRequestUpdate: {
        'adminRemarks': remarks.trim(),
        'approvedBy': approvedBy.trim(),
        'approvedByUid': _currentUid,
      },
    );

    await _createStatusNotification(
      request: request,
      requestId: requestRef.id,
      status: 'Approved',
      remarks: remarks,
      approvedBy: approvedBy,
      movementId: movementId,
    );

    await _createReceiverStatusNotification(
      request: request,
      requestId: requestRef.id,
      status: 'Approved',
      remarks: remarks,
      approvedBy: approvedBy,
      movementId: movementId,
    );
  }

  // ============================================================
  // APPROVE EDIT REQUEST
  // ============================================================

  /// Approves a request to hand an asset over, or to take it back.
  ///
  /// Runs the REAL assignment workflow - the same AssetService methods the
  /// direct path uses - rather than writing fields. That is what keeps holder,
  /// status and the stock split consistent: assignAsset moves every
  /// unassigned Head Office unit to the holder and sets assignedTo, and
  /// returnAsset gives them back and clears it. Both run in one transaction
  /// with this request's own status, so an approval cannot be applied twice.
  Future<void> _approveAssignmentRequest({
    required RequestModel request,
    required DocumentReference<Map<String, dynamic>> requestRef,
    required String remarks,
    required String approvedBy,
    required String assigneeId,
  }) async {
    final assetId = request.assetId.trim();

    if (assetId.isEmpty) {
      throw Exception('Asset ID is missing from the assignment request.');
    }

    final bookkeeping = <String, dynamic>{
      'adminRemarks': remarks.trim(),
      'approvedBy': approvedBy.trim(),
      'approvedByUid': _currentUid,
    };

    final holder = assigneeId.trim();

    if (holder.isNotEmpty) {
      await _assetService.assignAsset(
        assetId: assetId,
        userId: holder,
        approvalRequestRef: requestRef,
        approvalRequestUpdate: bookkeeping,
      );

      return;
    }

    await _assetService.returnAsset(
      assetId,
      approvalRequestRef: requestRef,
      approvalRequestUpdate: bookkeeping,
    );
  }

  /// The holder a legacy 'Edit' request was really asking for, or null when
  /// it is an ordinary edit and must stay one.
  ///
  /// Before 'Assignment' existed, the assistant filed assign and unassign as
  /// Edits whose proposed data differed from the previous data in the holder
  /// and nothing else. Approving those applied buildSafeEditUpdate, which
  /// deliberately never touches assignedTo - so the status changed, the holder
  /// did not, and both sides were told it had worked. Such a request is still
  /// sitting Pending in any database that predates the fix.
  ///
  /// Identification is deliberately narrow: the holder must have changed, and
  /// NOTHING outside the assignment workflow's own fields may have changed
  /// with it. A request that edits a name and a holder together is ambiguous,
  /// so it keeps ordinary Edit behaviour rather than being guessed at.
  ///
  /// An empty result means unassign; a non-empty one is the new holder.
  static String? _legacyAssignmentTarget(RequestModel request) {
    if (!request.isEditRequest) return null;

    final previous = request.previousAssetData;
    final proposed = request.proposedAssetData;

    if (previous == null || proposed == null) return null;
    if (previous.isEmpty || proposed.isEmpty) return null;

    String holderOf(Map<String, dynamic> data) =>
        (data['assignedTo'] ?? '').toString().trim();

    final before = holderOf(previous);
    final after = holderOf(proposed);

    // The holder is what an assignment changes. If it did not move, this is
    // an ordinary edit - including a status-only or add-stock request.
    if (before == after) return null;

    // Fields the assignment workflow owns and recomputes for itself. Anything
    // else differing makes the request a mixed edit, and its intent is no
    // longer unambiguous.
    const ownedByAssignment = <String>{
      'assignedTo',
      'status',
      'assignedQuantity',
      'headOfficeQuantity',
      'lastUpdated',
      'updatedAt',
    };

    for (final key in <String>{...previous.keys, ...proposed.keys}) {
      if (ownedByAssignment.contains(key)) continue;
      if ('${previous[key]}' == '${proposed[key]}') continue;

      return null;
    }

    return after;
  }

  /// Whether a destination names Head Office rather than a Bazaar.
  static bool _isHeadOffice(String name) =>
      name.trim().toLowerCase() == 'head office';

  Future<void> _approveEditRequest({
    required RequestModel request,
    required DocumentReference<Map<String, dynamic>> requestRef,
    required String remarks,
    required String approvedBy,
  }) async {
    if (request.assetId.trim().isEmpty) {
      throw Exception('Asset ID is missing from the edit request.');
    }

    final requestedData = request.proposedAssetData;

    if (requestedData == null || requestedData.isEmpty) {
      throw Exception('No proposed asset changes were found.');
    }

    // Apply only the fields the requester actually changed. The rest of the
    // form is a snapshot taken when the request was made; writing it back
    // would silently undo edits and movements made since then.
    final proposedData = _requestedChanges(
      previous: request.previousAssetData,
      proposed: requestedData,
    );

    final assetRef = _assets.doc(request.assetId.trim());

    // PRE-FLIGHT (outside the transaction): report ordinary validation errors
    // (e.g. quantity below allocated stock) before starting a transaction.
    // The same checks run again inside the transaction against the data it
    // commits on; throwing there is reserved for genuine races.
    final preflight = await assetRef.get();

    if (!preflight.exists || preflight.data() == null) {
      throw Exception('The requested asset no longer exists.');
    }

    AssetService.buildSafeEditUpdate(
      documentId: preflight.id,
      existingData: preflight.data()!,
      proposed: _assetFromProposedData(
        AssetModel.fromMap(preflight.data()!, preflight.id),
        proposedData,
      ).toMap(),
    );

    await _ensureEditKeepsIdentifiersUnique(
      documentId: preflight.id,
      proposed: proposedData,
    );

    final approverUid = _currentUid;

    await runGuardedTransaction(_firestore, (transaction) async {
      await _ensurePendingInTransaction(transaction, requestRef);

      final assetSnapshot = await transaction.get(assetRef);

      if (!assetSnapshot.exists || assetSnapshot.data() == null) {
        throw Exception('The requested asset no longer exists.');
      }

      final currentData = assetSnapshot.data()!;

      final currentAsset = AssetModel.fromMap(currentData, assetSnapshot.id);

      final updatedAsset = _assetFromProposedData(currentAsset, proposedData);

      // Only descriptive fields are applied. Stock distribution is recomputed
      // from the CURRENT stored stock at approval time, so stock moved after
      // the request was submitted can never be overwritten or lost.
      // Ownership (adminId/adminName) and assignment are never changed here.
      final assetData = AssetService.buildSafeEditUpdate(
        documentId: assetSnapshot.id,
        existingData: currentData,
        proposed: updatedAsset.toMap(),
      );

      transaction.update(assetRef, assetData);

      transaction.update(requestRef, {
        'status': 'Approved',
        'adminRemarks': remarks.trim(),
        'approvedBy': approvedBy.trim(),
        'approvedByUid': approverUid,
        'approvedDate': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Refuses an approval that would give two assets the same Asset ID or the
  /// same serial number.
  ///
  /// The edit form runs checkDuplicateAssetId/checkDuplicateSerial before it
  /// saves, but an approval writes straight to the asset and skipped them: a
  /// request filed while the identifier was still free, or two Pending requests
  /// naming the same one, both used to be approvable. Run as the approving
  /// manager, who may read the whole collection.
  ///
  /// [proposed] holds only the fields the requester actually changed, so an
  /// identifier that was not touched is not re-checked against itself.
  Future<void> _ensureEditKeepsIdentifiersUnique({
    required String documentId,
    required Map<String, dynamic> proposed,
  }) async {
    final assetId = _stringValue(proposed['assetId']);

    if (assetId.isNotEmpty &&
        await _assetService.checkDuplicateAssetId(
          assetId,
          excludeDocumentId: documentId,
        )) {
      throw Exception(
        'Asset ID "$assetId" already belongs to another asset, so this '
        'request cannot be approved.',
      );
    }

    final serialNumber = _stringValue(proposed['serialNumber']);

    if (serialNumber.isNotEmpty &&
        await _assetService.checkDuplicateSerial(
          serialNumber,
          excludeDocumentId: documentId,
        )) {
      throw Exception(
        'Serial number "$serialNumber" already belongs to another asset, so '
        'this request cannot be approved.',
      );
    }
  }

  Map<String, dynamic> _requestedChanges({
    required Map<String, dynamic>? previous,
    required Map<String, dynamic> proposed,
  }) {
    if (previous == null || previous.isEmpty) {
      return proposed;
    }

    Object? normalize(Object? value) {
      if (value is Timestamp) return value.millisecondsSinceEpoch;
      if (value is DateTime) return value.millisecondsSinceEpoch;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null && value.contains('-')) {
          return parsed.millisecondsSinceEpoch;
        }
        return value.trim();
      }
      if (value is num) return value.toDouble();
      return value;
    }

    final changes = <String, dynamic>{};

    proposed.forEach((key, value) {
      if (!previous.containsKey(key) ||
          normalize(previous[key]) != normalize(value)) {
        changes[key] = value;
      }
    });

    return changes;
  }

  // ============================================================
  // APPROVE DELETE REQUEST
  // ============================================================

  Future<void> _approveDeleteRequest({
    required RequestModel request,
    required DocumentReference<Map<String, dynamic>> requestRef,
    required String remarks,
    required String approvedBy,
  }) async {
    if (request.assetId.trim().isEmpty) {
      throw Exception('Asset ID is missing from the delete request.');
    }

    final cleanAssetId = request.assetId.trim();
    final assetRef = _assets.doc(cleanAssetId);

    // Refuse to orphan Active Bazaar movement records.
    await AssetService(
      firestore: _firestore,
    ).ensureAssetCanBeDeleted(cleanAssetId);

    final approverUid = _currentUid;

    await runGuardedTransaction(_firestore, (transaction) async {
      await _ensurePendingInTransaction(transaction, requestRef);

      await AssetService.deleteInTransaction(transaction, assetRef);

      transaction.update(requestRef, {
        'status': 'Approved',
        'adminRemarks': remarks.trim(),
        'approvedBy': approvedBy.trim(),
        'approvedByUid': approverUid,
        'approvedDate': FieldValue.serverTimestamp(),
      });
    });
  }

  // ============================================================
  // PENDING CHECK (inside transaction)
  // ============================================================

  Future<void> _ensurePendingInTransaction(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> requestRef,
  ) async {
    final snapshot = await transaction.get(requestRef);

    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      throw Exception('Request not found.');
    }

    final status = (data['status'] ?? '').toString().trim().toLowerCase();

    if (status != 'pending') {
      throw Exception('This request has already been processed.');
    }
  }

  // ============================================================
  // BUILD UPDATED ASSET
  // ============================================================

  AssetModel _assetFromProposedData(
    AssetModel current,
    Map<String, dynamic> data,
  ) {
    final hasPurchaseDate = data.containsKey('purchaseDate');

    final hasAssignedTo = data.containsKey('assignedTo');

    final assignedToValue = data['assignedTo'];

    return current.copyWith(
      assetId: _stringValue(data['assetId'], fallback: current.assetId),
      name: _stringValue(data['name'], fallback: current.name),
      category: _stringValue(data['category'], fallback: current.category),
      status: _stringValue(data['status'], fallback: current.status),
      quantity: _intValue(data['quantity'], fallback: current.quantity),
      serialNumber: _stringValue(
        data['serialNumber'],
        fallback: current.serialNumber,
      ),
      brand: _stringValue(data['brand'], fallback: current.brand),
      model: _stringValue(data['model'], fallback: current.model),
      purchasePrice: _doubleValue(
        data['purchasePrice'],
        fallback: current.purchasePrice,
      ),
      purchaseDate: hasPurchaseDate
          ? _dateValue(data['purchaseDate'])
          : current.purchaseDate,
      clearPurchaseDate: hasPurchaseDate && data['purchaseDate'] == null,
      warrantyMonths: _intValue(
        data['warrantyMonths'],
        fallback: current.warrantyMonths,
      ),
      location: _stringValue(data['location'], fallback: current.location),
      condition: _stringValue(data['condition'], fallback: current.condition),
      notes: _stringValue(data['notes'], fallback: current.notes),
      assignedTo: hasAssignedTo
          ? _nullableStringValue(assignedToValue)
          : current.assignedTo,
      clearAssignedTo: hasAssignedTo && assignedToValue == null,
      lastUpdated: DateTime.now(),
    );
  }

  // ============================================================
  // DELETE REQUEST DOCUMENT
  // ============================================================

  Future<void> deleteRequest(String requestId) async {
    final cleanId = requestId.trim();

    if (cleanId.isEmpty) {
      throw Exception('Request ID is required.');
    }

    final currentUid = _currentUid;

    if (currentUid.isEmpty) {
      throw Exception('You are not authenticated.');
    }

    final role = await _getCurrentRole();

    if (role != 'super_admin') {
      throw Exception('Only Super Admin can delete request records.');
    }

    await _requests.doc(cleanId).delete();
  }

  // ============================================================
  // GET USER REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getRequestsByUser(String userId) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return Stream.value(<RequestModel>[]);
    }

    return _requests
        .where('requestedBy', isEqualTo: cleanUserId)
        .snapshots()
        .map(_mapRequestSnapshot);
  }

  // ============================================================
  // GET PENDING REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getPendingRequests() {
    final uid = _currentUid;

    if (uid.isEmpty) {
      return Stream.value(<RequestModel>[]);
    }

    return _requests
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map(_mapRequestSnapshot);
  }

  // ============================================================
  // COUNTS
  // ============================================================

  Future<int> getRequestCount() async {
    final uid = _currentUid;

    if (uid.isEmpty) {
      return 0;
    }

    final role = await _getCurrentRole();

    if (role.isEmpty) {
      return 0;
    }

    Query<Map<String, dynamic>> query = _requests;

    // A manager counts every request, because that is what they now see and
    // may decide. Narrowing an Admin to receiverId made the badge disagree
    // with the list on the Requests screen.
    if (role == 'user') {
      query = query.where('requestedBy', isEqualTo: uid);
    }

    final snapshot = await query.get();

    return snapshot.docs.length;
  }

  Future<int> getPendingRequestCount() async {
    final uid = _currentUid;

    if (uid.isEmpty) {
      return 0;
    }

    final role = await _getCurrentRole();

    if (role.isEmpty) {
      return 0;
    }

    Query<Map<String, dynamic>> query = _requests.where(
      'status',
      isEqualTo: 'Pending',
    );

    // Same scope as [getRequestCount]: a manager counts all of them.
    if (role == 'user') {
      query = query.where('requestedBy', isEqualTo: uid);
    }

    final snapshot = await query.get();

    return snapshot.docs.length;
  }

  // ============================================================
  // CREATE NOTIFICATION
  // ============================================================

  Future<void> _createNotification({
    required String notificationId,
    required String userId,
    required String title,
    required String message,
    required String type,
    required String requestId,
    String movementId = '',
  }) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return;
    }

    final cleanNotificationId = notificationId.trim();

    if (cleanNotificationId.isEmpty) {
      return;
    }

    // Status notifications are written AFTER the approval/rejection has been
    // committed. A notification failure must not report the (already
    // successful) business operation as failed, so it is logged instead.
    try {
      await _notifications
          .doc(cleanNotificationId)
          .set(
            _notificationData(
              userId: cleanUserId,
              title: title,
              message: message,
              type: type,
              requestId: requestId,
              movementId: movementId,
            ),
            SetOptions(merge: false),
          );
    } catch (e) {
      debugPrint('Notification $cleanNotificationId could not be written: $e');
    }
  }

  void _addNotificationToBatch(
    WriteBatch batch, {
    required String notificationId,
    required String userId,
    required String title,
    required String message,
    required String type,
    required String requestId,
  }) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return;
    }

    batch.set(
      _notifications.doc(notificationId.trim()),
      _notificationData(
        userId: cleanUserId,
        title: title,
        message: message,
        type: type,
        requestId: requestId,
      ),
    );
  }

  Map<String, dynamic> _notificationData({
    required String userId,
    required String title,
    required String message,
    required String type,
    required String requestId,
    String movementId = '',
  }) {
    return {
      'title': title.trim(),
      'message': message.trim(),
      'type': type.trim(),
      'userId': userId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'requestId': requestId.trim(),
      'movementId': movementId.trim(),
    };
  }

  // ============================================================
  // REQUEST CREATED NOTIFICATION
  // ============================================================

  String _requestCreatedTitle(RequestModel request) {
    if (request.isTransferRequest) {
      return 'Transfer Request Submitted';
    }

    if (request.isEditRequest) {
      return 'Edit Request Submitted';
    }

    if (request.isDeleteRequest) {
      return 'Delete Request Submitted';
    }

    return 'Request Submitted';
  }

  String _requestCreatedMessage(RequestModel request) {
    final assetName = _requestAssetName(request);

    if (request.isTransferRequest) {
      final destination = request.destinationBazaarName.trim();

      if (destination.isEmpty) {
        return 'Your transfer request for $assetName has been submitted for approval.';
      }

      return 'Your transfer request for $assetName to $destination has been submitted for approval.';
    }

    return 'Your ${request.requestType.toLowerCase()} request for $assetName has been submitted for approval.';
  }

  // ============================================================
  // RECEIVER REQUEST NOTIFICATION
  // ============================================================

  String _receiverRequestTitle(RequestModel request) {
    if (request.isTransferRequest) {
      return 'New Asset Transfer Request';
    }

    if (request.isEditRequest) {
      return 'New Asset Edit Request';
    }

    if (request.isDeleteRequest) {
      return 'New Asset Delete Request';
    }

    return 'New Request';
  }

  String _receiverRequestMessage(RequestModel request) {
    final assetName = _requestAssetName(request);

    final requester = request.requestedUserName.trim();

    final destination = request.destinationBazaarName.trim();

    if (request.isTransferRequest) {
      final requesterText = requester.isNotEmpty
          ? '$requester requested'
          : 'An asset transfer was requested';

      if (destination.isNotEmpty) {
        return '$requesterText $assetName to $destination.';
      }

      return '$requesterText $assetName.';
    }

    if (request.isEditRequest) {
      return requester.isNotEmpty
          ? '$requester requested changes to $assetName.'
          : 'A user requested changes to $assetName.';
    }

    if (request.isDeleteRequest) {
      return requester.isNotEmpty
          ? '$requester requested deletion of $assetName.'
          : 'A user requested deletion of $assetName.';
    }

    return 'You have received a new request for $assetName.';
  }

  // ============================================================
  // STATUS NOTIFICATION
  // ============================================================

  Future<void> _createStatusNotification({
    required RequestModel request,
    required String requestId,
    required String status,
    required String remarks,
    required String approvedBy,
    String movementId = '',
  }) async {
    final requesterId = request.requestedBy.trim();

    if (requesterId.isEmpty) {
      return;
    }

    final normalizedStatus = status.trim().toLowerCase();

    final isApproved = normalizedStatus == 'approved';

    final actionWord = isApproved ? 'approved' : 'rejected';

    final requestTypeDisplay = _requestTypeDisplay(request);

    final decisionText = isApproved ? 'Approved' : 'Rejected';

    final title = request.isTransferRequest
        ? 'Transfer Request $decisionText'
        : '$requestTypeDisplay Request $decisionText';

    final message = _buildStatusMessage(
      request: request,
      status: actionWord,
      remarks: remarks,
      approvedBy: approvedBy,
    );

    await _createNotification(
      notificationId: '${requestId}_$normalizedStatus',
      userId: requesterId,
      title: title,
      message: message,
      type: isApproved ? 'request_approved' : 'request_rejected',
      requestId: requestId,
      movementId: movementId,
    );
  }

  // ============================================================
  // RECEIVER STATUS NOTIFICATION
  // ============================================================

  Future<void> _createReceiverStatusNotification({
    required RequestModel request,
    required String requestId,
    required String status,
    required String remarks,
    required String approvedBy,
    String movementId = '',
  }) async {
    final receiverId = request.receiverId.trim();

    final requesterId = request.requestedBy.trim();

    if (receiverId.isEmpty || receiverId == requesterId) {
      return;
    }

    final normalizedStatus = status.trim().toLowerCase();

    final isApproved = normalizedStatus == 'approved';

    final statusText = isApproved ? 'Approved' : 'Rejected';

    final assetName = _requestAssetName(request);

    final destination = request.destinationBazaarName.trim();

    String message;

    if (request.isTransferRequest) {
      message = 'Transfer request for $assetName has been $normalizedStatus';

      if (destination.isNotEmpty) {
        message += ' to $destination';
      }

      message += '.';
    } else {
      message = 'Request for $assetName has been $normalizedStatus.';
    }

    final cleanApprovedBy = approvedBy.trim();

    if (cleanApprovedBy.isNotEmpty) {
      message += ' Processed by $cleanApprovedBy.';
    }

    final cleanRemarks = remarks.trim();

    if (cleanRemarks.isNotEmpty) {
      message += ' Remarks: $cleanRemarks';
    }

    await _createNotification(
      notificationId: '${requestId}_receiver_$normalizedStatus',
      userId: receiverId,
      title: request.isTransferRequest
          ? 'Transfer Request $statusText'
          : 'Request $statusText',
      message: message,
      type: isApproved
          ? 'request_approved_receiver'
          : 'request_rejected_receiver',
      requestId: requestId,
      movementId: movementId,
    );
  }

  // ============================================================
  // BUILD STATUS MESSAGE
  // ============================================================

  String _buildStatusMessage({
    required RequestModel request,
    required String status,
    required String remarks,
    required String approvedBy,
  }) {
    final assetName = _requestAssetName(request);

    final buffer = StringBuffer();

    if (request.isTransferRequest) {
      buffer.write('Transfer request for $assetName has been $status');

      final destination = request.destinationBazaarName.trim();

      if (destination.isNotEmpty) {
        buffer.write(' to $destination');
      }

      buffer.write('.');
    } else {
      final requestTypeDisplay = _requestTypeDisplay(request);

      buffer.write(
        '$requestTypeDisplay request for $assetName has been $status.',
      );
    }

    final cleanApprovedBy = approvedBy.trim();

    if (cleanApprovedBy.isNotEmpty) {
      buffer.write(' Processed by $cleanApprovedBy.');
    }

    final cleanRemarks = remarks.trim();

    if (cleanRemarks.isNotEmpty) {
      buffer.write(' Remarks: $cleanRemarks');
    }

    return buffer.toString();
  }

  // ============================================================
  // REQUEST TYPE DISPLAY
  // ============================================================

  String _requestTypeDisplay(RequestModel request) {
    final type = request.requestType.trim();

    if (type.isEmpty) {
      return 'General';
    }

    final normalized = type.toLowerCase();

    if (normalized == 'edit') {
      return 'Edit';
    }

    if (normalized == 'delete') {
      return 'Delete';
    }

    if (normalized == 'transfer') {
      return 'Transfer';
    }

    if (normalized == 'add') {
      return 'Add';
    }

    return type;
  }

  // ============================================================
  // REQUEST ASSET NAME
  // ============================================================

  String _requestAssetName(RequestModel request) {
    final proposedData = request.proposedAssetData;

    if (proposedData != null) {
      final proposedName = _stringValue(proposedData['name']);

      if (proposedName.isNotEmpty) {
        return proposedName;
      }
    }

    final assetName = request.assetName.trim();

    if (assetName.isNotEmpty) {
      return assetName;
    }

    final assetId = request.assetId.trim();

    if (assetId.isEmpty) {
      return 'asset';
    }

    return 'asset $assetId';
  }

  // ============================================================
  // RESOLVE ASSET LOCATION
  // ============================================================

  String _resolveAssetLocation(AssetModel asset) {
    final currentBazaarName = (asset.currentBazaarName ?? '').trim();

    if (currentBazaarName.isNotEmpty) {
      return currentBazaarName;
    }

    final location = asset.location.trim();

    if (location.isNotEmpty) {
      return location;
    }

    return 'Head Office';
  }

  // ============================================================
  // VALUE HELPERS
  // ============================================================

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString().trim();

    return result.isEmpty ? fallback : result;
  }

  String? _nullableStringValue(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    if (result.isEmpty) {
      return null;
    }

    return result;
  }

  int _intValue(dynamic value, {int fallback = 0}) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? fallback;
  }

  double _doubleValue(dynamic value, {double fallback = 0.0}) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? fallback;
  }

  DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
