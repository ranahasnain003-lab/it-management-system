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
      // Services and Firestore rules both refuse in plain language; pass that
      // through rather than inventing a reason.
      return ActionResult.failure('That did not go through: ${_clean(error)}');
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
      // only see the inventory of the Admin they belong to. The Add Asset
      // form defaults to the signed-in account, and so does this.
      adminId: permissions.uid,
      adminName: permissions.displayName,
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
      receiverId: (asset.adminId ?? '').trim(),
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

  static String _clean(Object error) {
    var message = error.toString().trim();

    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }

    return message.isEmpty ? 'the change was rejected.' : message;
  }
}
