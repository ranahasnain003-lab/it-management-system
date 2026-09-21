import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/asset_model.dart';
import '../../models/deployment_model.dart';
import 'bazaar_service.dart';
import 'guarded_transaction.dart';

class DeploymentService {
  DeploymentService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _authOverride = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth? _authOverride;

  static const String _deploymentCollection = 'deployments';
  static const String _assetCollection = 'assets';
  static const String _bazaarCollection = 'bazaars';

  /// How a movement record names Head Office as a source or destination.
  ///
  /// Public because anything building a transfer has to use the same value:
  /// [transferAsset] requires a non-empty destination id, so a caller that
  /// invents its own sentinel (an empty string, say) is refused before
  /// [_isHeadOffice] is ever consulted.
  static const String headOfficeId = '__head_office__';
  static const String _headOfficeName = 'Head Office';

  /// Statuses whose stock physically no longer exists in the organization.
  /// Such stock can never be moved.
  static const Set<String> _nonTransferableStatuses = {
    'lost',
    'missing',
    'disposed',
    'retired',
    'deleted',
  };

  /// Operational statuses that a movement is allowed to recalculate.
  /// Any other status (Damaged, Under Repair, ...) is preserved.
  static const Set<String> _operationalStatuses = {
    '',
    'available',
    'assigned',
    'deployed',
    'in transit',
  };

  CollectionReference<Map<String, dynamic>> get _deployments =>
      _firestore.collection(_deploymentCollection);

  CollectionReference<Map<String, dynamic>> get _assets =>
      _firestore.collection(_assetCollection);

  CollectionReference<Map<String, dynamic>> get _bazaars =>
      _firestore.collection(_bazaarCollection);

  String _cleanId(String value) => value.trim();

  String _string(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;

    final result = value.toString().trim();
    return result.isEmpty ? fallback : result;
  }

  int _int(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value.toString()) ?? fallback;
  }

  int _nonNegativeInt(dynamic value) {
    final result = _int(value);
    return result < 0 ? 0 : result;
  }

  bool _isActiveStatus(dynamic value) {
    return _string(value).toLowerCase() == 'active';
  }

  bool _isHeadOffice(String id, String name) {
    final cleanId = id.trim().toLowerCase();
    final cleanName = name.trim().toLowerCase();

    return cleanId == headOfficeId.toLowerCase() ||
        cleanName == 'head office' ||
        cleanName == 'head-office' ||
        cleanName == 'head_office' ||
        cleanName == 'headoffice';
  }

  bool _sameLocation({
    required String firstId,
    required String firstName,
    required String secondId,
    required String secondName,
  }) {
    final aId = firstId.trim();
    final aName = firstName.trim().toLowerCase();
    final bId = secondId.trim();
    final bName = secondName.trim().toLowerCase();

    final aIsHeadOffice = _isHeadOffice(aId, aName);
    final bIsHeadOffice = _isHeadOffice(bId, bName);

    if (aIsHeadOffice || bIsHeadOffice) {
      return aIsHeadOffice && bIsHeadOffice;
    }

    // Bazaar names are not unique across cities. When both sides carry a
    // document ID, the ID is authoritative.
    if (aId.isNotEmpty && bId.isNotEmpty) {
      return aId == bId;
    }

    return aName.isNotEmpty && bName.isNotEmpty && aName == bName;
  }

  // ===========================================================================
  // UNIVERSAL ASSET TRANSFER
  //
  // Supported:
  //
  // Head Office -> Bazaar
  // Bazaar -> Bazaar
  // Bazaar -> Head Office
  //
  // STOCK RULE:
  //
  // quantity           = total physical stock
  // assignedQuantity   = stock assigned to users
  // deployedQuantity   = stock currently at ALL Bazaars
  // headOfficeQuantity = remaining unassigned stock at Head Office
  //
  // SINGLE SOURCE OF TRUTH:
  //
  // Total = Head Office + Assigned + Deployed
  //
  // Therefore:
  //
  // Head Office = Total - Assigned - Deployed
  // ===========================================================================

  Future<String> transferAsset({
    required String assetDocumentId,
    required String destinationId,
    required String destinationName,
    required int quantity,
    String transferredBy = '',
    String transferredByName = '',
    String receiverName = '',
    String receiverContact = '',
    String reason = '',
    String remarks = '',
    String sourceId = '',
    String sourceName = '',

    // When set, this specific Active movement must still hold at least
    // [quantity] units at commit time (prevents double returns/transfers
    // of the same movement record).
    String sourceDeploymentId = '',

    // When set, the referenced request must still be Pending at commit time
    // and is marked Approved in the SAME transaction as the stock movement.
    // This guarantees an approval is applied exactly once.
    DocumentReference<Map<String, dynamic>>? approvalRequestRef,
    Map<String, dynamic> approvalRequestUpdate = const {},
  }) async {
    final cleanAssetDocumentId = _cleanId(assetDocumentId);
    final cleanDestinationId = _cleanId(destinationId);
    final cleanDestinationName = destinationName.trim();
    final cleanSourceId = _cleanId(sourceId);
    final cleanSourceName = sourceName.trim();
    final cleanSourceDeploymentId = _cleanId(sourceDeploymentId);

    if (cleanAssetDocumentId.isEmpty) {
      throw Exception('Asset document ID is required.');
    }

    if (cleanDestinationId.isEmpty) {
      throw Exception('Destination is required.');
    }

    if (cleanDestinationName.isEmpty) {
      throw Exception('Destination name is required.');
    }

    if (quantity <= 0) {
      throw Exception('Transfer quantity must be greater than 0.');
    }

    final assetRef = _assets.doc(cleanAssetDocumentId);
    final newMovementRef = _deployments.doc();

    await _preflightTransfer(
      assetRef: assetRef,
      sourceId: cleanSourceId,
      sourceName: cleanSourceName,
      destinationId: cleanDestinationId,
      destinationName: cleanDestinationName,
      quantity: quantity,
      approvalRequestRef: approvalRequestRef,
      sourceDeploymentId: cleanSourceDeploymentId,
    );

    await runGuardedTransaction(_firestore, (transaction) async {
      final assetSnapshot = await transaction.get(assetRef);

      if (!assetSnapshot.exists) {
        throw Exception('Asset not found.');
      }

      final assetData = assetSnapshot.data();

      if (assetData == null) {
        throw Exception('Asset data not found.');
      }

      final currentStatus = _string(assetData['status']).toLowerCase();

      if (_nonTransferableStatuses.contains(currentStatus)) {
        throw Exception(
          'This asset is marked ${_string(assetData['status'])} and cannot be transferred.',
        );
      }

      // -----------------------------------------------------------------------
      // APPROVAL REQUEST (exactly-once)
      // -----------------------------------------------------------------------

      if (approvalRequestRef != null) {
        final requestSnapshot = await transaction.get(approvalRequestRef);

        if (!requestSnapshot.exists || requestSnapshot.data() == null) {
          throw Exception('Request not found.');
        }

        final requestStatus = _string(
          requestSnapshot.data()!['status'],
        ).toLowerCase();

        if (requestStatus != 'pending') {
          throw Exception('This request has already been processed.');
        }
      }

      // -----------------------------------------------------------------------
      // SPECIFIC SOURCE MOVEMENT
      // -----------------------------------------------------------------------

      if (cleanSourceDeploymentId.isNotEmpty) {
        final sourceMovement = await transaction.get(
          _deployments.doc(cleanSourceDeploymentId),
        );

        final sourceMovementData = sourceMovement.data();

        if (!sourceMovement.exists || sourceMovementData == null) {
          throw Exception('Deployment not found.');
        }

        if (!_isActiveStatus(sourceMovementData['status'])) {
          throw Exception('This movement is no longer active.');
        }

        if (_nonNegativeInt(sourceMovementData['quantity']) < quantity) {
          throw Exception(
            'This movement no longer holds $quantity unit(s). Please refresh and try again.',
          );
        }
      }

      // -----------------------------------------------------------------------
      // DESTINATION BAZAAR MUST EXIST AND BE ACTIVE
      // -----------------------------------------------------------------------

      if (!_isHeadOffice(cleanDestinationId, cleanDestinationName)) {
        final bazaarSnapshot = await transaction.get(
          _bazaars.doc(cleanDestinationId),
        );

        final bazaarData = bazaarSnapshot.data();

        if (!bazaarSnapshot.exists || bazaarData == null) {
          throw Exception('The selected destination Bazaar no longer exists.');
        }

        final bazaar = BazaarModel.fromFirestore(bazaarData, bazaarSnapshot.id);

        if (!bazaar.isActive) {
          throw Exception(
            '${bazaar.name.isEmpty ? 'The selected Bazaar' : bazaar.name} is disabled and cannot receive new transfers.',
          );
        }
      }

      // -----------------------------------------------------------------------
      // TOTAL STOCK
      // -----------------------------------------------------------------------

      final totalQuantity = _nonNegativeInt(assetData['quantity']);

      if (totalQuantity <= 0) {
        throw Exception('Asset quantity must be greater than 0.');
      }

      // -----------------------------------------------------------------------
      // ASSIGNED STOCK
      // -----------------------------------------------------------------------

      // Legacy documents have no assignedQuantity field; use the same
      // fallback as AssetModel so a movement never silently unassigns stock.
      final existingAssignedQuantity = assetData.containsKey('assignedQuantity')
          ? _nonNegativeInt(assetData['assignedQuantity'])
          : AssetModel.fromMap(
              assetData,
              cleanAssetDocumentId,
            ).calculatedAssignedQuantity;

      final assignedQuantity = existingAssignedQuantity > totalQuantity
          ? totalQuantity
          : existingAssignedQuantity;

      // -----------------------------------------------------------------------
      // ACTIVE DEPLOYMENTS
      //
      // Active deployment records represent the current physical stock
      // located at Bazaars.
      // -----------------------------------------------------------------------

      final deploymentSnapshot = await _deployments
          .where('assetDocumentId', isEqualTo: cleanAssetDocumentId)
          .where('status', isEqualTo: 'Active')
          .get();

      int totalDeployed = 0;

      for (final doc in deploymentSnapshot.docs) {
        final movementQuantity = _nonNegativeInt(doc.data()['quantity']);

        if (movementQuantity > 0) {
          totalDeployed += movementQuantity;
        }
      }

      if (assignedQuantity + totalDeployed > totalQuantity) {
        throw Exception(
          'Assigned and deployed quantities are greater than total asset quantity.',
        );
      }

      // -----------------------------------------------------------------------
      // HEAD OFFICE AVAILABLE STOCK
      // -----------------------------------------------------------------------

      final headOfficeAvailable =
          totalQuantity - assignedQuantity - totalDeployed;

      // -----------------------------------------------------------------------
      // RESOLVE SOURCE
      // -----------------------------------------------------------------------

      String resolvedSourceId = cleanSourceId;
      String resolvedSourceName = cleanSourceName;

      if (resolvedSourceId.isEmpty && resolvedSourceName.isEmpty) {
        final storedBazaarId = _string(assetData['currentBazaarId']);
        final storedBazaarName = _string(assetData['currentBazaarName']);
        final storedLocation = _string(assetData['location'], _headOfficeName);

        resolvedSourceId = storedBazaarId;
        resolvedSourceName = storedBazaarName.isEmpty
            ? storedLocation
            : storedBazaarName;
      }

      final sourceIsHeadOffice = _isHeadOffice(
        resolvedSourceId,
        resolvedSourceName,
      );

      String fromLocation;
      int sourceAvailable = 0;

      if (sourceIsHeadOffice) {
        fromLocation = _headOfficeName;
        sourceAvailable = headOfficeAvailable;
      } else {
        fromLocation = resolvedSourceName;

        if (fromLocation.isEmpty) {
          throw Exception('Current Bazaar information is missing.');
        }

        for (final doc in deploymentSnapshot.docs) {
          final data = doc.data();

          final movementBazaarId = _string(
            data['toBazaarId'] ?? data['bazaarId'],
          );

          final movementBazaarName = _string(
            data['toBazaarName'] ?? data['bazaarName'],
          );

          final movementQuantity = _nonNegativeInt(data['quantity']);

          if (movementQuantity <= 0) {
            continue;
          }

          if (_sameLocation(
            firstId: resolvedSourceId,
            firstName: resolvedSourceName,
            secondId: movementBazaarId,
            secondName: movementBazaarName,
          )) {
            sourceAvailable += movementQuantity;
          }
        }

        if (sourceAvailable <= 0) {
          throw Exception(
            'No quantity is currently available at $fromLocation.',
          );
        }
      }

      if (quantity > sourceAvailable) {
        throw Exception(
          'Only $sourceAvailable asset(s) are available at $fromLocation.',
        );
      }

      // -----------------------------------------------------------------------
      // DESTINATION
      // -----------------------------------------------------------------------

      final destinationIsHeadOffice = _isHeadOffice(
        cleanDestinationId,
        cleanDestinationName,
      );

      if (_sameLocation(
        firstId: resolvedSourceId,
        firstName: resolvedSourceName,
        secondId: cleanDestinationId,
        secondName: cleanDestinationName,
      )) {
        throw Exception(
          'Destination must be different from the current location.',
        );
      }

      // -----------------------------------------------------------------------
      // FINAL DEPLOYED STOCK
      //
      // ALL validation happens before the first transaction write, so an
      // aborted attempt never has queued writes (see _runGuardedTransaction).
      // -----------------------------------------------------------------------

      int finalDeployedQuantity;

      if (sourceIsHeadOffice && !destinationIsHeadOffice) {
        finalDeployedQuantity = totalDeployed + quantity;
      } else if (!sourceIsHeadOffice && destinationIsHeadOffice) {
        finalDeployedQuantity = totalDeployed - quantity;
      } else {
        // Bazaar -> Bazaar.
        finalDeployedQuantity = totalDeployed;
      }

      if (finalDeployedQuantity < 0) {
        throw Exception('Final deployed quantity cannot be negative.');
      }

      if (assignedQuantity + finalDeployedQuantity > totalQuantity) {
        throw Exception(
          'Assigned and deployed quantities cannot exceed total quantity.',
        );
      }

      // -----------------------------------------------------------------------
      // FINAL HEAD OFFICE STOCK
      // -----------------------------------------------------------------------

      final finalHeadOfficeQuantity =
          totalQuantity - assignedQuantity - finalDeployedQuantity;

      if (finalHeadOfficeQuantity < 0) {
        throw Exception('Final Head Office quantity cannot be negative.');
      }

      final now = DateTime.now();

      // -----------------------------------------------------------------------
      // REDUCE SOURCE BAZAAR STOCK
      // -----------------------------------------------------------------------

      if (!sourceIsHeadOffice) {
        int remainingToMove = quantity;

        final sourceDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        for (final doc in deploymentSnapshot.docs) {
          final data = doc.data();

          final movementBazaarId = _string(
            data['toBazaarId'] ?? data['bazaarId'],
          );

          final movementBazaarName = _string(
            data['toBazaarName'] ?? data['bazaarName'],
          );

          if (_sameLocation(
            firstId: resolvedSourceId,
            firstName: resolvedSourceName,
            secondId: movementBazaarId,
            secondName: movementBazaarName,
          )) {
            sourceDocs.add(doc);
          }
        }

        // The explicitly selected movement record is consumed first so the
        // history reflects exactly which record was returned/transferred.
        if (cleanSourceDeploymentId.isNotEmpty) {
          sourceDocs.sort((a, b) {
            if (a.id == cleanSourceDeploymentId) return -1;
            if (b.id == cleanSourceDeploymentId) return 1;
            return 0;
          });
        }

        final locatedAtSource = sourceDocs.fold<int>(
          0,
          (total, doc) => total + _nonNegativeInt(doc.data()['quantity']),
        );

        if (locatedAtSource < quantity) {
          throw Exception('Unable to locate enough quantity at $fromLocation.');
        }

        for (final sourceDoc in sourceDocs) {
          if (remainingToMove <= 0) {
            break;
          }

          final sourceData = sourceDoc.data();
          final sourceQuantity = _nonNegativeInt(sourceData['quantity']);

          if (sourceQuantity <= 0) {
            continue;
          }

          final movedFromThisRecord = remainingToMove > sourceQuantity
              ? sourceQuantity
              : remainingToMove;

          final remainingSourceQuantity = sourceQuantity - movedFromThisRecord;

          // HISTORY PRESERVATION:
          // The record's original route (fromLocation/toLocation), action
          // and original quantity are never overwritten. `quantity` is the
          // stock STILL at this Bazaar from this record; the onward movement
          // is described by the transferredTo* fields and by the new
          // movement record created below.
          final historyFields = <String, dynamic>{
            if (!sourceData.containsKey('originalQuantity'))
              'originalQuantity': sourceQuantity,
            'lastUpdated': Timestamp.fromDate(now),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          if (remainingSourceQuantity <= 0) {
            transaction.update(sourceDoc.reference, {
              ...historyFields,
              'quantity': 0,
              'status': destinationIsHeadOffice ? 'Returned' : 'Transferred',
              'transferDate': Timestamp.fromDate(now),
              'movedOutTo': cleanDestinationName,
              'transferredToBazaarId': destinationIsHeadOffice
                  ? null
                  : cleanDestinationId,
              'transferredToBazaarName': destinationIsHeadOffice
                  ? null
                  : cleanDestinationName,
              'transferredBy': transferredBy.trim(),
              'transferredByName': transferredByName.trim(),
            });
          } else {
            transaction.update(sourceDoc.reference, {
              ...historyFields,
              'quantity': remainingSourceQuantity,
            });
          }

          remainingToMove -= movedFromThisRecord;
        }
      }

      // -----------------------------------------------------------------------
      // CREATE DESTINATION MOVEMENT
      // -----------------------------------------------------------------------

      if (!destinationIsHeadOffice) {
        transaction.set(newMovementRef, {
          'assetDocumentId': cleanAssetDocumentId,
          'assetId': _string(assetData['assetId'], cleanAssetDocumentId),
          'assetName': _string(assetData['name'], 'Unnamed Asset'),
          'assetType': _string(assetData['category']),
          'serialNumber': _string(assetData['serialNumber']),

          // Owner of the inventory; scopes who may read this record.
          'adminId': _string(assetData['adminId']),

          'action':'transfer',

          'fromLocation': fromLocation,
          'toLocation': cleanDestinationName,

          'fromBazaarId': sourceIsHeadOffice || resolvedSourceId.isEmpty
              ? null
              : resolvedSourceId,

          'fromBazaarName': sourceIsHeadOffice || resolvedSourceName.isEmpty
              ? null
              : resolvedSourceName,

          'toBazaarId': cleanDestinationId,
          'toBazaarName': cleanDestinationName,

          'quantity': quantity,

          'sentBy': transferredBy.trim(),
          'sentByName': transferredByName.trim(),

          'deploymentDate': Timestamp.fromDate(now),

          'receiverName': receiverName.trim(),
          'receiverContact': receiverContact.trim(),

          'reason': reason.trim().isEmpty ? 'Asset Transfer' : reason.trim(),

          'remarks': remarks.trim(),
          'attachmentUrl': null,

          'status': 'Active',

          'createdAt': Timestamp.fromDate(now),
          'lastUpdated': Timestamp.fromDate(now),

          // Legacy compatibility.
          'bazaarId': cleanDestinationId,
          'bazaarName': cleanDestinationName,

          'deployedBy': transferredBy.trim(),
          'deployedByName': transferredByName.trim(),

          'movementType': 'Asset Transfer',
          'notes': remarks.trim(),
        });
      } else {
        transaction.set(newMovementRef, {
          'assetDocumentId': cleanAssetDocumentId,
          'assetId': _string(assetData['assetId'], cleanAssetDocumentId),
          'assetName': _string(assetData['name'], 'Unnamed Asset'),
          'assetType': _string(assetData['category']),
          'serialNumber': _string(assetData['serialNumber']),

          // Owner of the inventory; scopes who may read this record.
          'adminId': _string(assetData['adminId']),

          'action':'return',

          'fromLocation': fromLocation,
          'toLocation': _headOfficeName,

          'fromBazaarId': sourceIsHeadOffice || resolvedSourceId.isEmpty
              ? null
              : resolvedSourceId,

          'fromBazaarName': sourceIsHeadOffice || resolvedSourceName.isEmpty
              ? null
              : resolvedSourceName,

          'toBazaarId': null,
          'toBazaarName': null,

          'quantity': quantity,

          'sentBy': transferredBy.trim(),
          'sentByName': transferredByName.trim(),

          'deploymentDate': Timestamp.fromDate(now),
          'returnDate': Timestamp.fromDate(now),

          'receiverName': receiverName.trim(),
          'receiverContact': receiverContact.trim(),

          'reason': reason.trim().isEmpty
              ? 'Return to Head Office'
              : reason.trim(),

          'remarks': remarks.trim(),
          'attachmentUrl': null,

          'status': 'Returned',

          'createdAt': Timestamp.fromDate(now),
          'lastUpdated': Timestamp.fromDate(now),

          // Legacy compatibility.
          'bazaarId': sourceIsHeadOffice || resolvedSourceId.isEmpty
              ? null
              : resolvedSourceId,

          'bazaarName': sourceIsHeadOffice || resolvedSourceName.isEmpty
              ? null
              : resolvedSourceName,

          'deployedBy': transferredBy.trim(),
          'deployedByName': transferredByName.trim(),

          'movementType': 'Return to Head Office',
          'notes': remarks.trim(),
        });
      }

      // -----------------------------------------------------------------------
      // DETERMINE CURRENT LOCATION REPRESENTATION
      // -----------------------------------------------------------------------

      String finalLocation = _headOfficeName;
      String? finalCurrentBazaarId;
      String? finalCurrentBazaarName;

      if (finalDeployedQuantity <= 0) {
        finalLocation = _headOfficeName;
        finalCurrentBazaarId = null;
        finalCurrentBazaarName = null;
      } else {
        final uniqueBazaars = <String, Map<String, String>>{};

        // Existing active deployments.
        for (final doc in deploymentSnapshot.docs) {
          final data = doc.data();

          final bazaarId = _string(data['toBazaarId'] ?? data['bazaarId']);

          final bazaarName = _string(
            data['toBazaarName'] ?? data['bazaarName'],
          );

          final movementQuantity = _nonNegativeInt(data['quantity']);

          if (movementQuantity <= 0 ||
              (bazaarId.isEmpty && bazaarName.isEmpty)) {
            continue;
          }

          final key = bazaarId.isNotEmpty
              ? 'id:$bazaarId'
              : 'name:${bazaarName.toLowerCase()}';

          uniqueBazaars[key] = {'id': bazaarId, 'name': bazaarName};
        }

        // Destination is a new active Bazaar movement.
        if (!destinationIsHeadOffice) {
          final key = cleanDestinationId.isNotEmpty
              ? 'id:$cleanDestinationId'
              : 'name:${cleanDestinationName.toLowerCase()}';

          uniqueBazaars[key] = {
            'id': cleanDestinationId,
            'name': cleanDestinationName,
          };
        }

        // Remove source Bazaar when all of its stock was moved.
        if (!sourceIsHeadOffice) {
          int remainingSourceStock = 0;

          for (final doc in deploymentSnapshot.docs) {
            final data = doc.data();

            final bazaarId = _string(data['toBazaarId'] ?? data['bazaarId']);

            final bazaarName = _string(
              data['toBazaarName'] ?? data['bazaarName'],
            );

            final movementQuantity = _nonNegativeInt(data['quantity']);

            if (_sameLocation(
              firstId: resolvedSourceId,
              firstName: resolvedSourceName,
              secondId: bazaarId,
              secondName: bazaarName,
            )) {
              remainingSourceStock += movementQuantity;
            }
          }

          final remainingAfterTransfer = remainingSourceStock - quantity;

          if (remainingAfterTransfer <= 0) {
            final sourceKey = resolvedSourceId.isNotEmpty
                ? 'id:$resolvedSourceId'
                : 'name:${resolvedSourceName.toLowerCase()}';

            uniqueBazaars.remove(sourceKey);
          }
        }

        if (uniqueBazaars.length == 1) {
          final onlyBazaar = uniqueBazaars.values.first;

          finalCurrentBazaarId = onlyBazaar['id'];
          finalCurrentBazaarName = onlyBazaar['name'];

          final bazaarName = (onlyBazaar['name'] ?? '').trim();

          finalLocation = bazaarName.isEmpty
              ? 'Multiple Locations'
              : bazaarName;
        } else {
          finalLocation = 'Multiple Locations';
          finalCurrentBazaarId = null;
          finalCurrentBazaarName = null;
        }
      }

      // -----------------------------------------------------------------------
      // UPDATE ASSET AGGREGATES
      //
      // IMPORTANT:
      // quantity NEVER changes during a transfer.
      // -----------------------------------------------------------------------

      // Damaged / Under Repair (and any other non-operational status) is a
      // condition of the asset and must survive a movement.
      final finalStatus = _operationalStatuses.contains(currentStatus)
          ? (assignedQuantity > 0 || finalDeployedQuantity > 0
                ? 'Assigned'
                : 'Available')
          : _string(assetData['status']);

      transaction.update(assetRef, {
        'quantity': totalQuantity,

        'headOfficeQuantity': finalHeadOfficeQuantity,
        'assignedQuantity': assignedQuantity,
        'deployedQuantity': finalDeployedQuantity,

        'location': finalLocation,
        'currentBazaarId': finalCurrentBazaarId,
        'currentBazaarName': finalCurrentBazaarName,

        'deploymentStatus': finalDeployedQuantity > 0
            ? 'Deployed'
            : 'At Head Office',

        'status': finalStatus,

        'lastUpdated': Timestamp.fromDate(now),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (approvalRequestRef != null) {
        transaction.update(approvalRequestRef, {
          ...approvalRequestUpdate,
          'status': 'Approved',
          'approvedDate': FieldValue.serverTimestamp(),
          'movementId': newMovementRef.id,
          'deploymentId': newMovementRef.id,
        });
      }
    });

    return newMovementRef.id;
  }

  // ===========================================================================
  // PRE-FLIGHT VALIDATION
  //
  // Ordinary user errors (quantity above stock, disabled destination, already
  // processed request, same location) are reported BEFORE the transaction.
  // The transaction repeats every check against the data it commits on, so
  // concurrent changes are still caught there; this pre-check only avoids
  // throwing inside the transaction handler for the common cases (the
  // cloud_firestore method-channel implementation can surface a secondary
  // "Future already completed" error when a handler throws and the native
  // side retries).
  // ===========================================================================

  Future<void> _preflightTransfer({
    required DocumentReference<Map<String, dynamic>> assetRef,
    required String sourceId,
    required String sourceName,
    required String destinationId,
    required String destinationName,
    required int quantity,
    DocumentReference<Map<String, dynamic>>? approvalRequestRef,
    String sourceDeploymentId = '',
  }) async {
    if (sourceDeploymentId.isNotEmpty) {
      final movement = await _deployments.doc(sourceDeploymentId).get();
      final data = movement.data();

      if (!movement.exists || data == null) {
        throw Exception('Deployment not found.');
      }

      if (!_isActiveStatus(data['status'])) {
        throw Exception('This movement is no longer active.');
      }

      if (_nonNegativeInt(data['quantity']) < quantity) {
        throw Exception(
          'This movement no longer holds $quantity unit(s). Please refresh and try again.',
        );
      }
    }

    if (approvalRequestRef != null) {
      final request = await approvalRequestRef.get();

      if (!request.exists || request.data() == null) {
        throw Exception('Request not found.');
      }

      if (_string(request.data()!['status']).toLowerCase() != 'pending') {
        throw Exception('This request has already been processed.');
      }
    }

    final assetSnapshot = await assetRef.get();
    final assetData = assetSnapshot.data();

    if (!assetSnapshot.exists || assetData == null) {
      throw Exception('Asset not found.');
    }

    final status = _string(assetData['status']).toLowerCase();

    if (_nonTransferableStatuses.contains(status)) {
      throw Exception(
        'This asset is marked ${_string(assetData['status'])} and cannot be transferred.',
      );
    }

    if (sourceId.isNotEmpty || sourceName.isNotEmpty) {
      if (_sameLocation(
        firstId: sourceId,
        firstName: sourceName,
        secondId: destinationId,
        secondName: destinationName,
      )) {
        throw Exception(
          'Destination must be different from the current location.',
        );
      }
    }

    if (!_isHeadOffice(destinationId, destinationName)) {
      final bazaar = await _bazaars.doc(destinationId).get();

      if (!bazaar.exists || bazaar.data() == null) {
        throw Exception('The selected destination Bazaar no longer exists.');
      }

      final model = BazaarModel.fromFirestore(bazaar.data()!, bazaar.id);

      if (!model.isActive) {
        throw Exception(
          '${model.name.isEmpty ? 'The selected Bazaar' : model.name} is disabled and cannot receive new transfers.',
        );
      }
    }

    final active = await _deployments
        .where('assetDocumentId', isEqualTo: assetRef.id)
        .where('status', isEqualTo: 'Active')
        .get();

    if (_isHeadOffice(sourceId, sourceName) ||
        (sourceId.isEmpty && sourceName.isEmpty)) {
      final total = _nonNegativeInt(assetData['quantity']);
      final assigned = assetData.containsKey('assignedQuantity')
          ? _nonNegativeInt(assetData['assignedQuantity'])
          : AssetModel.fromMap(
              assetData,
              assetRef.id,
            ).calculatedAssignedQuantity;
      final deployed = active.docs.fold<int>(
        0,
        (total, doc) => total + _nonNegativeInt(doc.data()['quantity']),
      );

      if (sourceId.isNotEmpty || sourceName.isNotEmpty) {
        final available = total - assigned - deployed;

        if (quantity > available) {
          throw Exception(
            'Only ${available < 0 ? 0 : available} asset(s) are available at Head Office.',
          );
        }
      }

      return;
    }

    var atSource = 0;

    for (final doc in active.docs) {
      final data = doc.data();

      if (_sameLocation(
        firstId: sourceId,
        firstName: sourceName,
        secondId: _string(data['toBazaarId'] ?? data['bazaarId']),
        secondName: _string(data['toBazaarName'] ?? data['bazaarName']),
      )) {
        atSource += _nonNegativeInt(data['quantity']);
      }
    }

    if (quantity > atSource) {
      throw Exception(
        'Only $atSource asset(s) are available at ${sourceName.isEmpty ? 'the source Bazaar' : sourceName}.',
      );
    }
  }

  // ===========================================================================
  // GET DEPLOYMENT BY ID
  // ===========================================================================

  Future<DeploymentModel?> getDeploymentById(String deploymentId) async {
    final cleanDeploymentId = _cleanId(deploymentId);

    if (cleanDeploymentId.isEmpty) {
      return null;
    }

    final snapshot = await _deployments.doc(cleanDeploymentId).get();

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    return DeploymentModel.fromFirestore(data, snapshot.id);
  }

  // ===========================================================================
  // ALL MOVEMENT HISTORY
  // ===========================================================================

  Stream<List<DeploymentModel>> getDeployments() {
    return _scopedMovements((query) => query);
  }

  // ===========================================================================
  // MOVEMENT VISIBILITY
  //
  // Super Admin / Admin: every movement record.
  // User: only records of inventory owned by the Admin the User belongs to
  // (the same `adminId` scope firestore.rules enforce), so a User never sees
  // other Admins' movements, receivers or contacts.
  // ===========================================================================

  /// Null = unrestricted; empty = nothing visible; otherwise the Admin UID.
  Future<String?> _movementScopeAdminId() async {
    final auth = _authOverride ?? FirebaseAuth.instance;
    final uid = auth.currentUser?.uid ?? '';

    if (uid.isEmpty) {
      return '';
    }

    final profile = await _firestore.collection('users').doc(uid).get();
    final data = profile.data() ?? const <String, dynamic>{};
    final role = _string(data['role']).toLowerCase();

    if (role == 'super_admin' || role == 'admin') {
      return null;
    }

    return _string(data['createdBy']);
  }

  /// Wrapped in [Stream.fromFuture] so a scope lookup that finishes after the
  /// listener was cancelled (logout / account switch) is discarded with it.
  Stream<List<DeploymentModel>> _scopedMovements(
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> query)
    build,
  ) {
    return Stream<String?>.fromFuture(_movementScopeAdminId()).asyncExpand((
      adminId,
    ) {
      if (adminId != null && adminId.isEmpty) {
        return Stream.value(const <DeploymentModel>[]);
      }

      Query<Map<String, dynamic>> query = _deployments;

      if (adminId != null) {
        query = query.where('adminId', isEqualTo: adminId);
      }

      return build(query).snapshots().map((snapshot) {
        final deployments = snapshot.docs
            .map((doc) => DeploymentModel.fromFirestore(doc.data(), doc.id))
            .toList();

        deployments.sort(
          (a, b) => b.deploymentDate.compareTo(a.deploymentDate),
        );

        return deployments;
      });
    });
  }

  /// Gives records created before movement records carried `adminId` the
  /// owner of their asset. Runs from a Super Admin session (the only role
  /// that can see every record); already-migrated records are skipped.
  Future<int> backfillMovementOwners() async {
    final snapshot = await _deployments.get();
    final assetOwners = <String, String>{};
    var updated = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();

      if (data.containsKey('adminId')) {
        continue;
      }

      final assetDocumentId = _string(data['assetDocumentId']);

      if (assetDocumentId.isEmpty) {
        continue;
      }

      if (!assetOwners.containsKey(assetDocumentId)) {
        final asset = await _assets.doc(assetDocumentId).get();
        assetOwners[assetDocumentId] = _string(asset.data()?['adminId']);
      }

      // One write per record: a malformed legacy record rejected by the
      // rules must not block the migration of all the others.
      try {
        await doc.reference.update({'adminId': assetOwners[assetDocumentId]});
        updated++;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
      }
    }

    return updated;
  }

  // ===========================================================================
  // MOVEMENT HISTORY FOR ONE ASSET
  // ===========================================================================

  Stream<List<DeploymentModel>> getDeploymentsForAsset(String assetId) {
    final cleanAssetId = _cleanId(assetId);

    if (cleanAssetId.isEmpty) {
      return Stream.value(<DeploymentModel>[]);
    }

    return _scopedMovements(
      (query) => query.where('assetDocumentId', isEqualTo: cleanAssetId),
    );
  }

  // ===========================================================================
  // ACTIVE BAZAAR MOVEMENTS
  //
  // ONLY Active records represent current Bazaar stock.
  // Transferred/Returned records remain history only.
  // ===========================================================================

  Stream<List<DeploymentModel>> getActiveDeployments() {
    return _scopedMovements(
      (query) => query.where('status', isEqualTo: 'Active'),
    );
  }

  // ===========================================================================
  // ASSETS CURRENTLY AT BAZAARS
  //
  // Aggregate view:
  // calculatedDeployedQuantity = quantity currently deployed
  // across ALL Bazaars.
  // ===========================================================================

  Stream<List<AssetModel>> getAssetsAtBazaars() {
    return _assets.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
          .where((asset) => asset.calculatedDeployedQuantity > 0)
          .toList();
    });
  }

  // ===========================================================================
  // ASSETS FOR A SPECIFIC BAZAAR
  //
  // IMPORTANT:
  //
  // quantity             = quantity physically at THIS Bazaar
  // deployedQuantity     = aggregate deployed quantity across ALL Bazaars
  // assignedQuantity     = organization-level assigned quantity
  // headOfficeQuantity   = organization-level Head Office quantity
  //
  // Example:
  //
  // Total = 15
  // Bazaar A = 5
  // Bazaar B = 4
  // Head Office = 6
  //
  // Bazaar A screen:
  //
  // quantity = 5
  // deployedQuantity = 9
  //
  // NOT deployedQuantity = 5.
  // ===========================================================================

  Stream<List<AssetModel>> getAssetsForBazaar(String bazaarId) {
    final cleanBazaarId = _cleanId(bazaarId);

    if (cleanBazaarId.isEmpty) {
      return Stream.value(<AssetModel>[]);
    }

    return _deployments
        .where('toBazaarId', isEqualTo: cleanBazaarId)
        .where('status', isEqualTo: 'Active')
        .snapshots()
        .asyncMap((deploymentSnapshot) async {
          // -------------------------------------------------------------------
          // SUM ACTIVE QUANTITY FOR THIS BAZAAR ONLY.
          // -------------------------------------------------------------------

          final Map<String, int> quantitiesByAsset = {};

          final Map<String, String> bazaarNamesByAsset = {};

          for (final deploymentDoc in deploymentSnapshot.docs) {
            final data = deploymentDoc.data();

            final assetDocumentId = _string(
              data['assetDocumentId'] ?? data['assetDocId'] ?? data['assetId'],
            );

            if (assetDocumentId.isEmpty) {
              continue;
            }

            final quantity = _nonNegativeInt(data['quantity']);

            if (quantity <= 0) {
              continue;
            }

            quantitiesByAsset[assetDocumentId] =
                (quantitiesByAsset[assetDocumentId] ?? 0) + quantity;

            final bazaarName = _string(
              data['toBazaarName'] ?? data['bazaarName'],
            );

            if (bazaarName.isNotEmpty) {
              bazaarNamesByAsset[assetDocumentId] = bazaarName;
            }
          }

          final List<AssetModel> assets = [];

          for (final entry in quantitiesByAsset.entries) {
            final assetSnapshot = await _assets.doc(entry.key).get();

            if (!assetSnapshot.exists) {
              continue;
            }

            final assetData = assetSnapshot.data();

            if (assetData == null) {
              continue;
            }

            final originalAsset = AssetModel.fromMap(
              assetData,
              assetSnapshot.id,
            );

            // This is the CURRENT stock physically at the
            // selected Bazaar.
            final bazaarQuantity = entry.value;

            // This remains the ORIGINAL total physical stock.
            final totalQuantity = originalAsset.quantity;

            // These are organization-level aggregate buckets.
            final assignedQuantity = originalAsset.calculatedAssignedQuantity;

            final deployedQuantity = originalAsset.calculatedDeployedQuantity;

            final safeBazaarQuantity = bazaarQuantity.clamp(0, totalQuantity);

            final safeAssignedQuantity = assignedQuantity.clamp(
              0,
              totalQuantity,
            );

            final safeDeployedQuantity = deployedQuantity.clamp(
              0,
              totalQuantity,
            );

            final safeHeadOfficeQuantity =
                (totalQuantity - safeAssignedQuantity - safeDeployedQuantity)
                    .clamp(0, totalQuantity);

            final bazaarName =
                bazaarNamesByAsset[entry.key] ??
                originalAsset.currentBazaarName ??
                cleanBazaarId;

            assets.add(
              originalAsset.copyWith(
                // IMPORTANT:
                // On a Bazaar-specific screen quantity is scoped
                // to that Bazaar.
                quantity: safeBazaarQuantity,

                // These remain aggregate organization-level values.
                headOfficeQuantity: safeHeadOfficeQuantity,

                assignedQuantity: safeAssignedQuantity,

                deployedQuantity: safeDeployedQuantity,

                // This screen represents the selected Bazaar.
                location: bazaarName,

                currentBazaarId: cleanBazaarId,

                currentBazaarName: bazaarName,

                deploymentStatus: 'Deployed',
              ),
            );
          }

          return assets;
        });
  }

  // ===========================================================================
  // LEGACY DEPLOYMENT API
  //
  // Disabled intentionally.
  // TransferAsset is the single movement workflow.
  // ===========================================================================

  Future<String> deployAsset({
    required AssetModel asset,
    required String bazaarId,
    required String bazaarName,
    required String sentBy,
    String sentByName = '',
    String receiverName = '',
    String receiverContact = '',
    String reason = '',
    String remarks = '',
    String? attachmentUrl,
    int? deploymentQuantity,
  }) async {
    throw Exception(
      'Deploy Asset has been removed. Use Transfer Asset instead.',
    );
  }

  // ===========================================================================
  // BAZAAR -> BAZAAR
  // ===========================================================================

  Future<String> markDeploymentTransferred({
    required String deploymentId,
    required String newBazaarId,
    required String newBazaarName,
    required String assetDocumentId,
    String transferredBy = '',
    String transferredByName = '',
    String notes = '',
  }) async {
    final cleanDeploymentId = _cleanId(deploymentId);

    final cleanAssetDocumentId = _cleanId(assetDocumentId);

    final cleanNewBazaarId = _cleanId(newBazaarId);

    final cleanNewBazaarName = newBazaarName.trim();

    if (cleanDeploymentId.isEmpty) {
      throw Exception('Deployment ID is required.');
    }

    if (cleanAssetDocumentId.isEmpty) {
      throw Exception('Asset document ID is required.');
    }

    if (cleanNewBazaarId.isEmpty) {
      throw Exception('Destination Bazaar is required.');
    }

    if (cleanNewBazaarName.isEmpty) {
      throw Exception('Destination Bazaar name is required.');
    }

    final deploymentSnapshot = await _deployments.doc(cleanDeploymentId).get();

    if (!deploymentSnapshot.exists) {
      throw Exception('Deployment not found.');
    }

    final deploymentData = deploymentSnapshot.data();

    if (deploymentData == null) {
      throw Exception('Deployment data not found.');
    }

    if (!_isActiveStatus(deploymentData['status'])) {
      throw Exception('This movement is no longer active.');
    }

    final quantity = _nonNegativeInt(deploymentData['quantity']);

    if (quantity <= 0) {
      throw Exception('Invalid deployment quantity.');
    }

    final sourceBazaarId = _string(
      deploymentData['toBazaarId'] ?? deploymentData['bazaarId'],
    );

    final sourceBazaarName = _string(
      deploymentData['toBazaarName'] ?? deploymentData['bazaarName'],
    );

    return transferAsset(
      assetDocumentId: cleanAssetDocumentId,
      sourceId: sourceBazaarId,
      sourceName: sourceBazaarName,
      destinationId: cleanNewBazaarId,
      destinationName: cleanNewBazaarName,
      quantity: quantity,
      transferredBy: transferredBy,
      transferredByName: transferredByName,
      remarks: notes,
      reason: 'Bazaar to Bazaar Transfer',
      sourceDeploymentId: cleanDeploymentId,
    );
  }

  // ===========================================================================
  // RETURN TO HEAD OFFICE
  // ===========================================================================

  Future<void> returnAsset({
    required String deploymentId,
    required String assetDocumentId,
    String remarks = '',
  }) async {
    final cleanDeploymentId = _cleanId(deploymentId);

    final cleanAssetDocumentId = _cleanId(assetDocumentId);

    if (cleanDeploymentId.isEmpty) {
      throw Exception('Deployment ID is required.');
    }

    if (cleanAssetDocumentId.isEmpty) {
      throw Exception('Asset document ID is required.');
    }

    final deploymentSnapshot = await _deployments.doc(cleanDeploymentId).get();

    if (!deploymentSnapshot.exists) {
      throw Exception('Deployment not found.');
    }

    final deploymentData = deploymentSnapshot.data();

    if (deploymentData == null) {
      throw Exception('Deployment data not found.');
    }

    if (!_isActiveStatus(deploymentData['status'])) {
      throw Exception('This movement is no longer active.');
    }

    final quantity = _nonNegativeInt(deploymentData['quantity']);

    if (quantity <= 0) {
      throw Exception('Invalid deployment quantity.');
    }

    final sourceBazaarId = _string(
      deploymentData['toBazaarId'] ?? deploymentData['bazaarId'],
    );

    final sourceBazaarName = _string(
      deploymentData['toBazaarName'] ?? deploymentData['bazaarName'],
    );

    await transferAsset(
      assetDocumentId: cleanAssetDocumentId,
      sourceId: sourceBazaarId,
      sourceName: sourceBazaarName,
      destinationId: headOfficeId,
      destinationName: _headOfficeName,
      quantity: quantity,
      remarks: remarks,
      reason: 'Return to Head Office',
      sourceDeploymentId: cleanDeploymentId,
    );
  }

  // ===========================================================================
  // DELETE MOVEMENT
  //
  // Movement history must NEVER be deleted.
  // ===========================================================================

  Future<void> deleteDeployment(String deploymentId) async {
    final cleanDeploymentId = _cleanId(deploymentId);

    if (cleanDeploymentId.isEmpty) {
      throw Exception('Deployment ID is required.');
    }

    final snapshot = await _deployments.doc(cleanDeploymentId).get();

    if (!snapshot.exists) {
      throw Exception('Movement not found.');
    }

    throw Exception('Asset movement history cannot be deleted.');
  }
}
