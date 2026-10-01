import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../../models/asset_model.dart';
import '../../models/request_model.dart';
import '../services/asset_service.dart';
import '../services/bazaar_service.dart';
import '../services/deployment_service.dart';
import '../services/request_service.dart';
import 'assistant_actions.dart';

/// Carries out an action the user has confirmed.
///
/// Every branch here is a call into a service the app already uses. There is
/// no Firestore access, no stock arithmetic and no permission logic of its
/// own: the services keep their validation, their transactions, their audit
/// records, and Firestore rules still have the final say. If a service refuses,
/// the refusal is what the user is shown.
class ActionExecutor {
  ActionExecutor({
    AssetService? assetService,
    DeploymentService? deploymentService,
    BazaarService? bazaarService,
    RequestService? requestService,
  }) : _assetOverride = assetService,
       _movementOverride = deploymentService,
       _bazaarOverride = bazaarService,
       _requestOverride = requestService;

  final AssetService? _assetOverride;
  final DeploymentService? _movementOverride;
  final BazaarService? _bazaarOverride;
  final RequestService? _requestOverride;

  // Built on first use. A default service reaches for FirebaseFirestore.instance
  // in its constructor, so creating all four up front would require a Firebase
  // app even for an action that touches none of them.
  late final AssetService _assets = _assetOverride ?? AssetService();
  late final DeploymentService _movements = _movementOverride ?? DeploymentService();
  late final BazaarService _bazaars = _bazaarOverride ?? BazaarService();
  late final RequestService _requests = _requestOverride ?? RequestService();

  /// Shown in the movement and request records so an entry made through the
  /// assistant is identifiable in the history afterwards.
  static const String _reason = 'AI Assistant';

  Future<ActionResult> run(
    AssistantAction action,
    AssistantPermissions permissions,
  ) async {
    try {
      if (action.viaRequest) {
        return await _fileRequest(action, permissions);
      }

      switch (action.kind) {
        case AssistantActionKind.openScreen:
          // Navigation is the caller's job; nothing is written.
          return const ActionResult.success('Opening that screen for you.');

        case AssistantActionKind.sendToBazaar:
        case AssistantActionKind.moveBetweenBazaars:
        case AssistantActionKind.returnToHeadOffice:
          return await _transfer(action, permissions);

        case AssistantActionKind.assign:
          await _assets.assignAsset(
            assetId: action.asset!.id,
            userId: action.assigneeUid,
          );
          return ActionResult.success(
            'Done. ${_label(action.asset!)} is now assigned to ${action.assigneeName}.',
          );

        case AssistantActionKind.unassign:
          await _assets.returnAsset(action.asset!.id);
          return ActionResult.success(
            'Done. ${_label(action.asset!)} has been taken back and the stock is '
            'at Head Office.',
          );

        case AssistantActionKind.updateStatus:
          await _assets.updateAssetStatus(
            assetId: action.asset!.id,
            status: action.status,
          );
          return ActionResult.success(
            'Done. ${_label(action.asset!)} is now marked ${action.status}.',
          );

        case AssistantActionKind.addStock:
          return await _addStock(action);

        case AssistantActionKind.createAsset:
          return await _createAsset(action, permissions);

        case AssistantActionKind.createBazaar:
          await _bazaars.createBazaar(
            name: action.subjectName,
            location: action.subjectLocation,
            // The create rule requires the writer to own the record it is
            // adding, so this is the signed-in account, never the resolved
            // inventory owner: a Bazaar belongs to nobody's inventory.
            createdBy: permissions.uid,
            createdByName: permissions.displayName,
          );
          return ActionResult.success(
            'Done. "${action.subjectName}" has been added to the Bazaar list.',
          );

        case AssistantActionKind.disableBazaar:
          await _bazaars.updateBazaarStatus(
            bazaarId: action.destinationId,
            isActive: false,
          );
          return ActionResult.success(
            'Done. ${action.subjectName} is now disabled. The record is kept.',
          );
      }
    } catch (error) {
      return ActionResult.failure(_refusal(error));
    }
  }

  // ------------------------------------------------------------------ moves

  Future<ActionResult> _transfer(
    AssistantAction action,
    AssistantPermissions permissions,
  ) async {
    await _movements.transferAsset(
      assetDocumentId: action.asset!.id,
      destinationId: action.destinationId,
      destinationName: action.destinationName,
      quantity: action.quantity,
      sourceId: action.sourceId,
      sourceName: action.sourceName,
      transferredBy: permissions.uid,
      transferredByName: permissions.displayName,
      reason: _reason,
    );

    return ActionResult.success(
      'Done. ${_units(action.quantity)} of ${_label(action.asset!)} moved from '
      '${action.sourceName} to ${action.destinationName}. It is recorded in the '
      'transfer history.',
    );
  }

  // ------------------------------------------------------------------ stock

  Future<ActionResult> _addStock(AssistantAction action) async {
    final asset = action.asset!;

    // The stock fields stay consistent because the new units are added to both
    // the total and the Head Office share; the other shares are untouched.
    final updated = asset.copyWith(
      quantity: asset.quantity + action.quantity,
      headOfficeQuantity: asset.calculatedHeadOfficeQuantity + action.quantity,
      lastUpdated: DateTime.now(),
    );

    await _assets.updateAsset(asset.id, updated);

    return ActionResult.success(
      'Done. ${_label(asset)} now holds ${_units(updated.quantity)}; the '
      '${_units(action.quantity)} were added at Head Office.',
    );
  }

  Future<ActionResult> _createAsset(
    AssistantAction action,
    AssistantPermissions permissions,
  ) async {
    final draft = action.draft;

    if (draft == null) {
      return const ActionResult.failure(
        'I did not have the details for that asset, so I did not create it.',
      );
    }

    // The planner already refused an account it could not resolve an owner
    // for; this repeats the check because an asset written under the wrong
    // account is worse than one not written at all.
    final ownerUid = resolveAssetOwnerUid(permissions);

    if (ownerUid.isEmpty) {
      return const ActionResult.failure(
        'I could not tell whose inventory that asset would belong to, so I '
        'did not create it.',
      );
    }

    // Informational only, and only knowable when the owner is the signed-in
    // account: a User cannot read the directory their Admin's name is in.
    final ownerName =
        ownerUid == permissions.uid.trim() ? permissions.displayName : '';

    // AssetService.addAsset derives the stock fields from the quantity
    // (headOffice = quantity, assigned = 0, deployed = 0) and reserves the
    // Asset ID, exactly as it does for the Add Asset form, so none of that is
    // repeated here.
    final asset = AssetModel(
      id: '',
      assetId: draft.assetId,
      name: draft.name,
      category: draft.category,
      status: draft.status,
      quantity: draft.quantity,
      serialNumber: draft.serialNumber,
      brand: draft.brand,
      model: draft.model,
      purchasePrice: draft.purchasePrice,
      purchaseDate: draft.purchaseDate,
      warrantyMonths: draft.warrantyMonths,
      location: draft.location,
      condition: draft.condition,
      notes: draft.notes,
      // Every asset needs an owning Admin: the rules require it, and Users
      // only see the inventory of the Admin they belong to. Resolved by the
      // one rule the Add Asset form uses, not by a second copy of it.
      adminId: ownerUid,
      adminName: ownerName,
      // The create rule recognises a User's own new asset by this field, so
      // without it a User's add is refused. It is the signed-in account, not
      // the owner: a User's asset belongs to their Admin but was created by
      // them.
      createdBy: permissions.uid.trim(),
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

    await _assets.addAsset(asset);

    return ActionResult.success(
      'Done. ${draft.assetId} ("${draft.name}") has been created with '
      '${_units(draft.quantity)} at ${draft.location}.',
    );
  }

  // --------------------------------------------------------------- requests

  /// A normal user cannot change inventory directly, so the assistant files the
  /// same request an Admin would review on the Requests screen. The approval
  /// workflow is unchanged: nothing moves until an Admin approves it.
  Future<ActionResult> _fileRequest(
    AssistantAction action,
    AssistantPermissions permissions,
  ) async {
    final asset = action.asset;

    if (asset == null) {
      return const ActionResult.failure(
        'I could not tell which asset that request is for, so I did not send it.',
      );
    }

    final isTransfer = action.kind == AssistantActionKind.sendToBazaar ||
        action.kind == AssistantActionKind.moveBetweenBazaars ||
        action.kind == AssistantActionKind.returnToHeadOffice;

    // Handing an asset to somebody, or taking it back, is its own kind of
    // request. Filed as an Edit it was applied by the descriptive-field
    // editor, which never touches assignedTo or the stock split - so the
    // status changed and the holder did not, and both sides were told it had
    // worked.
    final isAssignment = action.kind == AssistantActionKind.assign ||
        action.kind == AssistantActionKind.unassign;

    final request = RequestModel(
      requestType: isTransfer
          ? 'Transfer'
          : (isAssignment ? 'Assignment' : 'Edit'),
      assetId: asset.id,
      assetName: asset.name,
      category: asset.category,
      reason: _requestReason(action),
      priority: 'Medium',
      requestedBy: permissions.uid,
      requestedUserName: permissions.displayName,
      // Deliberately left for RequestService to route. A User now reads the
      // whole organisation's inventory, so the asset's owning Admin is often
      // not the Admin who manages the requester - and the create rule only
      // accepts a User's request routed to their OWN Admin (or left unrouted).
      // Naming the asset's owner here earned a permission-denied after the
      // user had already confirmed; RequestService fills in the requester's
      // own Admin from their profile, which is exactly what the rule expects.
      receiverId: '',
      status: 'Pending',
      requestDate: DateTime.now(),
      sourceBazaarId: isTransfer ? action.sourceId : '',
      sourceBazaarName: isTransfer ? action.sourceName : '',
      destinationBazaarId: isTransfer ? action.destinationId : '',
      destinationBazaarName: isTransfer ? action.destinationName : '',
      transferQuantity: isTransfer ? action.quantity : 0,
      transferRemarks: isTransfer ? _reason : '',
      // Empty for an unassignment, which is what tells the approval to take
      // the asset back rather than hand it over.
      assigneeId: action.kind == AssistantActionKind.assign
          ? action.assigneeUid
          : '',
      assigneeName: action.kind == AssistantActionKind.assign
          ? action.assigneeName
          : '',
      previousAssetData: isTransfer ? null : asset.toMap(),
      proposedAssetData: isTransfer ? null : _proposedData(action, asset),
    );

    await _requests.createRequest(request);

    return ActionResult.success(
      'Sent. Your request is with your Admin now, and nothing changes until it '
      'is approved. You can follow it on the Requests screen.',
    );
  }

  static String _requestReason(AssistantAction action) {
    final lines = <String>[action.title, ...action.details];
    return 'Requested through the AI Assistant.\n${lines.join('\n')}';
  }

  /// The asset as the user asked for it, for the Admin to approve or reject.
  static Map<String, dynamic> _proposedData(
    AssistantAction action,
    AssetModel asset,
  ) {
    switch (action.kind) {
      case AssistantActionKind.updateStatus:
        return asset.copyWith(status: action.status).toMap();

      case AssistantActionKind.addStock:
        return asset
            .copyWith(
              quantity: asset.quantity + action.quantity,
              headOfficeQuantity:
                  asset.calculatedHeadOfficeQuantity + action.quantity,
            )
            .toMap();

      case AssistantActionKind.unassign:
        return asset.copyWith(clearAssignedTo: true, status: 'Available').toMap();

      case AssistantActionKind.assign:
        return asset
            .copyWith(assignedTo: action.assigneeUid, status: 'Assigned')
            .toMap();

      default:
        return asset.toMap();
    }
  }

  // ---------------------------------------------------------------- helpers

  static String _label(AssetModel asset) {
    final tag = asset.assetId.trim();
    return tag.isEmpty ? asset.name : '$tag (${asset.name})';
  }

  static String _units(int value) => value == 1 ? '1 unit' : '$value units';

  /// What the user is told when a confirmed change was refused.
  ///
  /// The services phrase their own refusals for the user ("Asset ID ... already
  /// exists.", "Only 5 units are at Head Office."), so those are passed
  /// through: they say more than anything this could invent. Firebase does not
  /// - its messages name collections, rules files and line numbers - so each
  /// code that a user can actually hit gets a sentence of its own, and anything
  /// unrecognised is kept short rather than leaking internals.
  static String _refusal(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Your account is not allowed to make this change.';

        case 'unavailable':
        case 'deadline-exceeded':
          return 'I could not reach the database. Check your connection and '
              'try again; nothing was changed.';

        case 'not-found':
          return 'That record no longer exists.';

        default:
          return 'That did not go through. Nothing was changed.';
      }
    }

    final message = _clean(error);

    return message.isEmpty
        ? 'That did not go through. Nothing was changed.'
        : 'That did not go through: $message';
  }

  /// The message out of a service's own refusal, or an empty string for an
  /// error that was never meant to be read by the user.
  static String _clean(Object error) {
    final text = error.toString().trim();

    // `Exception: <sentence>` is how every service in the app refuses. An
    // error in any other shape is a fault, not a refusal, and its text would
    // mean nothing to the user.
    if (!text.startsWith('Exception: ')) return '';

    return text.substring('Exception: '.length).trim();
  }
}
