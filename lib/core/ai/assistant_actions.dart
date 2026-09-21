import 'package:flutter/foundation.dart';

import '../../models/asset_model.dart';
import '../services/permission_service.dart';

/// The kinds of change the assistant is allowed to propose.
///
/// Every one of these is carried out by an existing service method. The
/// assistant adds no stock arithmetic, no Firestore writes and no rules of its
/// own: it only works out what the user meant, checks it, and asks first.
enum AssistantActionKind {
  /// Add units of an existing asset to Head Office stock.
  addStock,

  /// Create a new asset record.
  createAsset,

  /// Head Office -> Bazaar.
  sendToBazaar,

  /// Bazaar -> Bazaar.
  moveBetweenBazaars,

  /// Bazaar -> Head Office.
  returnToHeadOffice,

  /// Give an asset to a person.
  assign,

  /// Take an assigned asset back.
  unassign,

  /// Change an asset's status (Available, Damaged, Under Repair, ...).
  updateStatus,

  /// Add a Bazaar to the master list.
  createBazaar,

  /// Mark a Bazaar inactive. Bazaars are never deleted.
  disableBazaar,

  /// Navigate to an existing screen. Changes nothing.
  openScreen,
}

/// Whether a kind of action writes to the database.
///
/// Only [AssistantActionKind.openScreen] does not, and it is the only one that
/// skips the confirmation step.
bool actionWrites(AssistantActionKind kind) => kind != AssistantActionKind.openScreen;

/// A change the assistant proposes, fully resolved and already checked.
///
/// Every field is taken from the account's own permission-scoped snapshot
/// before this object is built, so it can never name an asset, a Bazaar, a
/// person or a quantity that the account cannot already see.
class AssistantAction {
  const AssistantAction({
    required this.kind,
    required this.title,
    required this.details,
    this.asset,
    this.quantity = 0,
    this.sourceId = '',
    this.sourceName = '',
    this.destinationId = '',
    this.destinationName = '',
    this.assigneeUid = '',
    this.assigneeName = '',
    this.status = '',
    this.subjectName = '',
    this.subjectLocation = '',
    this.route = '',
    this.viaRequest = false,
    this.draft,
  });

  final AssistantActionKind kind;

  /// One line naming the change, shown as the heading of the preview.
  final String title;

  /// The specifics, one per line, so the user confirms against real figures.
  final List<String> details;

  final AssetModel? asset;
  final int quantity;

  /// Empty id plus the name "Head Office" is how the transfer service already
  /// identifies Head Office; Bazaars carry their document id.
  final String sourceId;
  final String sourceName;
  final String destinationId;
  final String destinationName;

  final String assigneeUid;
  final String assigneeName;

  final String status;

  final String subjectName;
  final String subjectLocation;

  /// Route to open, for [AssistantActionKind.openScreen].
  final String route;

  /// The new asset, for [AssistantActionKind.createAsset].
  final NewAssetDraft? draft;

  /// True when the account may not make the change directly and the assistant
  /// will file it through the existing approval workflow instead.
  final bool viaRequest;

  bool get writes => actionWrites(kind);

  /// The label on the confirm button.
  String get confirmLabel => viaRequest ? 'Send request' : 'Confirm';
}

/// A new asset as the user described it, ready to be shown for confirmation.
///
/// Only fields the user actually supplied are set. The remaining defaults are
/// the ones the Add Asset form itself starts with, and every stored value is
/// listed in the confirmation, so nothing is filled in behind the user's back.
class NewAssetDraft {
  const NewAssetDraft({
    required this.assetId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.purchasePrice,
    this.status = 'Available',
    this.condition = 'Good',
    this.location = 'Head Office',
    this.brand = '',
    this.model = '',
    this.serialNumber = '',
    this.purchaseDate,
    this.warrantyMonths = 0,
    this.notes = '',
  });

  /// The four the Add Asset form marks required, plus the category, which has
  /// no neutral default and must not be guessed.
  final String assetId;
  final String name;
  final String category;
  final int quantity;
  final double purchasePrice;

  final String status;
  final String condition;
  final String location;

  final String brand;
  final String model;
  final String serialNumber;
  final DateTime? purchaseDate;
  final int warrantyMonths;
  final String notes;

  static String _money(double value) => value == value.roundToDouble()
      ? 'Rs.${value.round()}'
      : 'Rs.${value.toStringAsFixed(2)}';

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Every value that will be stored, so the user confirms against the real
  /// record rather than a summary of it.
  List<String> previewLines() {
    final total = purchasePrice * quantity;

    return [
      'Asset ID: $assetId',
      'Name: $name',
      'Category: $category',
      'Quantity: ${quantity == 1 ? '1 unit' : '$quantity units'}',
      'Unit purchase price: ${_money(purchasePrice)}',
      'Total value: ${_money(total)}',
      'Status: $status',
      'Condition: $condition',
      'Location: $location',
      if (brand.isNotEmpty) 'Brand: $brand',
      if (model.isNotEmpty) 'Model: $model',
      if (serialNumber.isNotEmpty) 'Serial number: $serialNumber',
      if (purchaseDate != null) 'Purchase date: ${_date(purchaseDate!)}',
      if (warrantyMonths > 0) 'Warranty: $warrantyMonths month(s)',
      if (notes.isNotEmpty) 'Notes: $notes',
    ];
  }
}

/// What the planner decided about a message.
///
/// Exactly one of [action], [question] and [refusal] is set. A null plan means
/// "this was not a command", and the read-only assistant answers instead.
class ActionPlan {
  const ActionPlan._({this.action, this.question, this.refusal});

  /// A change to show the user for confirmation.
  const ActionPlan.propose(AssistantAction action) : this._(action: action);

  /// Something is missing or ambiguous. The assistant asks rather than guesses.
  const ActionPlan.ask(String question) : this._(question: question);

  /// The account may not do this, or the numbers do not work.
  const ActionPlan.refuse(String reason) : this._(refusal: reason);

  final AssistantAction? action;
  final String? question;
  final String? refusal;

  bool get isProposal => action != null;

  /// The text to show when this plan is not a proposal.
  String get message => question ?? refusal ?? '';
}

/// The result of carrying an action out.
class ActionResult {
  const ActionResult({required this.ok, required this.message});

  const ActionResult.success(String message) : this(ok: true, message: message);
  const ActionResult.failure(String message) : this(ok: false, message: message);

  final bool ok;
  final String message;
}

/// What the signed-in account is allowed to do, read once from the profile.
///
/// This is a thin, testable view over [PermissionService]; it defines no new
/// rules. Firestore rules and the services remain the real enforcement - this
/// only decides what the assistant will offer, so the user is told "you cannot
/// do that" instead of watching a write get rejected.
class AssistantPermissions {
  const AssistantPermissions({
    required this.role,
    this.uid = '',
    this.displayName = '',
    this.roles = const <String>[],
    this.customPermissions = const <String>[],
  });

  /// An account with no profile loaded: allowed to do nothing.
  static const AssistantPermissions none = AssistantPermissions(role: '');

  final String role;
  final String uid;
  final String displayName;
  final List<String> roles;
  final List<String> customPermissions;

  bool get isSuperAdmin => PermissionService.isSuperAdmin(role);
  bool get isAdmin => PermissionService.isAdmin(role);
  bool get isNormalUser => PermissionService.isUser(role);

  String get roleLabel => PermissionService.roleLabel(role);

  bool get canAddAsset => PermissionService.canCreateAsset(
    role,
    roles: roles,
    permissions: customPermissions,
  );

  bool get canEditAsset => PermissionService.canEditAsset(
    role,
    roles: roles,
    permissions: customPermissions,
  );

  bool get canTransfer => PermissionService.canTransferAsset(
    role,
    roles: roles,
    permissions: customPermissions,
  );

  bool get canAssign => PermissionService.canAssignAsset(
    role,
    roles: roles,
    permissions: customPermissions,
  );

  bool get canReturn => PermissionService.canReturnAsset(
    role,
    roles: roles,
    permissions: customPermissions,
  );

  bool get canChangeStatus => PermissionService.canChangeAssetStatus(
    role,
    roles: roles,
    permissions: customPermissions,
  );

  /// Bazaars are locations; the app already gates them on manage_locations.
  bool get canManageBazaars => PermissionService.canManageLocations(
    role,
    roles: roles,
    permissions: customPermissions,
  );

  /// Whether this account files changes as requests for an Admin to approve.
  bool get worksThroughRequests => isNormalUser;

  /// What this account may be offered, named the way the language model names
  /// it, so the model does not propose a change the user would only be
  /// refused for.
  ///
  /// This is a wording hint and nothing else. It grants no power: it travels
  /// to the backend as ordinary request data, and every proposal that comes
  /// back is re-checked against these same permissions by ActionPlanner before
  /// the user is even shown a confirmation. Firestore rules remain the real
  /// enforcement, which is why nothing is lost if this list is wrong.
  List<String> get assistantCapabilities => [
    if (canEditAsset || worksThroughRequests) 'addStock',
    if (canAddAsset) 'createAsset',
    if (canTransfer || worksThroughRequests) ...[
      'sendToBazaar',
      'moveBetweenBazaars',
      'returnToHeadOffice',
    ],
    if (canAssign || worksThroughRequests) 'assign',
    if (canReturn || worksThroughRequests) 'unassign',
    if (canChangeStatus || worksThroughRequests) 'updateStatus',
    if (canManageBazaars) ...['createBazaar', 'disableBazaar'],
  ];
}

/// A change the language model believes the user asked for.
///
/// **Nothing here is trusted.** These are loose strings the model copied out of
/// the facts it was shown; none of them is an id and none of them has been
/// checked. [ActionPlanner.planFromIntent] looks every one of them up again in
/// the account's own permission-scoped snapshot, re-runs every quantity, stock,
/// permission and invariant check, and the result still goes behind the Confirm
/// button before anything is written.
@immutable
class AssistantIntent {
  const AssistantIntent({
    required this.kind,
    this.assetRef = '',
    this.quantity,
    this.fromLocation = '',
    this.toLocation = '',
    this.personName = '',
    this.status = '',
    this.bazaarName = '',
    this.screen = '',
    this.newAsset = const <String, dynamic>{},
  });

  /// Matches the name of an [AssistantActionKind] value. An unknown kind is
  /// dropped before an intent is ever built.
  final String kind;

  /// Asset ID, serial number or name, as the model read it off the facts.
  final String assetRef;

  final int? quantity;
  final String fromLocation;
  final String toLocation;
  final String personName;
  final String status;
  final String bazaarName;
  final String screen;

  /// Fields for a proposed new asset. Only used for `createAsset`.
  final Map<String, dynamic> newAsset;

  /// Characters that must never survive into a generated command sentence or
  /// a confirmation dialog: control characters and newlines (which would let
  /// a value paint extra lines into the preview the user is approving),
  /// angle brackets, and commas (the planner reads `Field: value, Field:
  /// value` lists).
  static final RegExp _unsafe = RegExp(r'[\u0000-\u001f\u007f<>,]');

  static final RegExp _runsOfSpace = RegExp(r'\s+');

  /// One line of plain text, capped.
  ///
  /// This deliberately repeats what the backend already does to the same
  /// values. The backend is a network service: under any threat model where
  /// its reply is attacker-controlled, its cleaning is not a layer at all, so
  /// the app cannot be the only thing relying on it.
  static String _text(Object? value, [int cap = 120]) {
    if (value is! String) return '';

    final flattened =
        value.replaceAll(_unsafe, ' ').replaceAll(_runsOfSpace, ' ').trim();

    return flattened.length <= cap ? flattened : flattened.substring(0, cap);
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Reads an intent off the callable's response, or null when there is none.
  static AssistantIntent? fromMap(Object? value) {
    if (value is! Map) return null;

    final map = value.cast<Object?, Object?>();
    final kind = _text(map['kind']);
    if (kind.isEmpty) return null;

    final draft = map['newAsset'];

    return AssistantIntent(
      kind: kind,
      assetRef: _text(map['assetRef']),
      quantity: _int(map['quantity']),
      fromLocation: _text(map['fromLocation']),
      toLocation: _text(map['toLocation']),
      personName: _text(map['personName']),
      status: _text(map['status'], 40),
      bazaarName: _text(map['bazaarName']),
      screen: _text(map['screen'], 40),
      newAsset: draft is Map
          ? {
              // Cleaned like every other value: these end up in the
              // confirmation the user approves, and in a `Field: value` list
              // the planner reads back.
              for (final entry in draft.entries)
                entry.key.toString(): entry.value is String
                    ? _text(entry.value, 200)
                    : entry.value,
            }
          : const <String, dynamic>{},
    );
  }
}
