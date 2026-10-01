import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/user_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/asset_scope.dart';
import '../../providers/bazaar_provider.dart';
import '../../providers/deployment_provider.dart';
import '../../providers/request_provider.dart';
import '../../providers/user_provider.dart';
import '../inventory_snapshot_builder.dart';
import 'local_ai_context_service.dart';
import 'local_ai_inventory_context.dart';

/// Supplies the Local AI server with IT Management System data, read through
/// the same providers - and so the same Firebase login, services and
/// firestore.rules - as the app's own screens.
///
/// This class only gathers: it starts the listeners the in-app assistant
/// starts, waits (briefly) for them, and hands plain values to
/// [LocalAiInventoryContext.build], which decides what may be sent and
/// shapes it. Nothing is cached between questions except which asset or
/// Bazaar the conversation is about, and that is resolved again against the
/// live records every time.
class ProviderInventoryContextService implements LocalAiContextService {
  ProviderInventoryContextService({
    required this._assets,
    required this._bazaars,
    required this._deployments,
    required this._users,
    required this._requests,
    this._settleTimeout = const Duration(seconds: 8),
    this._pollInterval = const Duration(milliseconds: 120),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AssetProvider _assets;
  final BazaarProvider _bazaars;
  final DeploymentProvider _deployments;
  final UserProvider _users;
  final RequestProvider _requests;

  /// How long one question waits, in all, for the profile and the listeners:
  /// the same bound the in-app assistant panel uses. A slow or failed stream
  /// then becomes a "still loading" note instead of a question that never
  /// returns.
  final Duration _settleTimeout;
  final Duration _pollInterval;
  final DateTime Function() _clock;

  /// What the conversation is about, for a follow-up two questions later
  /// ("and its warranty?"). Held per account and dropped by [reset].
  String? _memoryUid;
  String? _lastAssetId;
  String? _lastBazaar;

  /// The profile of the session this service last started the movement
  /// listener in.
  ///
  /// DeploymentProvider.listenToDeployments restarts its stream on every call,
  /// unlike the other providers' listeners, and has no "listening" flag. So it
  /// is started only when it has failed, or holds nothing and was not started
  /// in this session. The profile object stands for the session: a sign-out
  /// clears the provider and a sign-in loads a new profile object, even for
  /// the same account, so an emptied provider is never mistaken for a
  /// Firestore with no movements.
  UserModel? _movementsStartedWith;

  String get _signedInUid => _users.currentUserUid?.trim() ?? '';

  bool get _manager => _users.isSuperAdmin || _users.isAdmin;

  @override
  Future<LocalAiAppContext?> contextFor({
    required String question,
    required String? uid,
    String? previousQuestion,
    required int budgetTokens,
  }) async {
    final asked = uid?.trim() ?? '';
    if (asked.isEmpty || _signedInUid.isEmpty) return null;

    if (_memoryUid != _signedInUid) {
      _forget();
      _memoryUid = _signedInUid;
    }

    // One deadline for both waits below, so a slow session restore cannot
    // double the wait and outlast the caller's own timeout, which would
    // replace this service's specific "still loading" notes with a generic
    // failure.
    final waited = Stopwatch()..start();

    // A session restored a moment ago may still be reading its profile.
    // Waiting for it is better than refusing a question it could answer.
    if (_users.currentUserProfile == null && _users.isLoadingCurrentUser) {
      await _waitUntil(() => !_users.isLoadingCurrentUser, waited);
    }

    final refused = _accessProblem(asked);
    if (refused != null) return _withoutData(refused);

    // A greeting needs no records, so none are read and nothing waits for the
    // listeners: "Hello" should not sit behind an inventory load. The
    // follow-up memory is left as it was.
    if (LocalAiInventoryContext.isSmallTalk(question)) {
      return _withoutData(LocalAiInventoryContext.smallTalkNote);
    }

    final needsRequests = LocalAiInventoryContext.needsRequests(
      question,
      previousQuestion: previousQuestion,
    );

    _startListeners(needsRequests: needsRequests);

    await _waitUntil(() => _settled(needsRequests: needsRequests), waited);

    // The account can be signed out, switched, disabled or demoted while the
    // listeners settle. Everything is checked again before a record is read.
    if (_signedInUid.isEmpty) return null;

    final changed = _accessProblem(asked);
    if (changed != null) return _withoutData(changed);

    try {
      final result = LocalAiInventoryContext.build(
        LocalAiContextInputs(
          question: question,
          previousQuestion: previousQuestion,
          askedForUid: asked,
          signedInUid: _signedInUid,
          role: _users.currentUserRole,
          profile: _users.currentUserProfile,
          snapshot: inventorySnapshotFromProviders(
            assets: _assets,
            bazaars: _bazaars,
            deployments: _deployments,
            users: _users,
          ),
          requests: needsRequests ? _requests.requests : const [],
          people: _manager ? _users.users : const [],
          inventoryState: LocalAiSourceState(
            loading: AssetScope.isSettling(users: _users, assets: _assets),
            // AssetProvider also keeps the last failed action's message here;
            // only a stopped listener means the inventory itself failed.
            error: _assets.isListening ? null : _assets.errorMessage,
          ),
          movementState: LocalAiSourceState(
            loading: _deployments.isLoading,
            error: _deployments.error,
          ),
          bazaarState: LocalAiSourceState(
            loading: _bazaars.isLoading,
            error: _bazaars.isListening ? null : _bazaars.errorMessage,
          ),
          requestState: needsRequests
              ? LocalAiSourceState(
                  loading: _requests.isLoading,
                  error: _requests.isListening ? null : _requests.errorMessage,
                )
              : LocalAiSourceState.ready,
          peopleState: LocalAiSourceState(
            loading: _manager && _users.isLoading,
            // UserProvider shares one message between its listener and its
            // actions, so it only speaks for the list when the list is empty.
            error: _users.users.isEmpty ? _users.errorMessage : null,
          ),
          inventoryInScope: _inventoryInScope(),
          rememberedAssetId: _lastAssetId,
          rememberedBazaar: _lastBazaar,
          retrievedAt: _clock(),
          budgetTokens: budgetTokens,
        ),
      );

      _remember(result);
      return result.context;
    } catch (error) {
      // Only the type is logged: the message could quote a record.
      debugPrint('Local AI context could not be built: ${error.runtimeType}');
      return _withoutData(
        'The inventory could not be read for this question because of an '
        'unexpected error in the app.',
      );
    }
  }

  @override
  void reset() {
    _forget();
    _memoryUid = null;
    _movementsStartedWith = null;
  }

  void _forget() {
    _lastAssetId = null;
    _lastBazaar = null;
  }

  void _remember(LocalAiContextResult result) {
    final asset = result.focusAsset;
    final bazaar = result.focusBazaar;

    if (asset != null) {
      _lastAssetId = asset.id;
      _lastBazaar = null;
    } else if (bazaar != null) {
      _lastBazaar = bazaar;
      _lastAssetId = null;
    }
  }

  String? _accessProblem(String asked) {
    return LocalAiInventoryContext.accessProblem(
      askedForUid: asked,
      signedInUid: _signedInUid,
      profile: _users.currentUserProfile,
      role: _users.currentUserRole,
    );
  }

  LocalAiAppContext _withoutData(String note) {
    return LocalAiInventoryContext.withoutData(
      role: _users.currentUserRole,
      retrievedAt: _clock(),
      notes: [note],
    );
  }

  // ---------------------------------------------------------------- listeners

  /// Starts the listeners the in-app assistant panel starts, plus the request
  /// listener when the question is about requests.
  ///
  /// Each call is safe to repeat: the asset, Bazaar, request and user
  /// providers ignore a request for a listener that is already running, and
  /// the movement listener is guarded here.
  void _startListeners({required bool needsRequests}) {
    try {
      AssetScope.listenForRole(users: _users, assets: _assets);
      _bazaars.listenToBazaars();

      final session = _users.currentUserProfile;
      final movementsNeeded =
          _deployments.hasError ||
          (_deployments.deployments.isEmpty &&
              !_deployments.isLoading &&
              !identical(_movementsStartedWith, session));
      if (movementsNeeded) {
        _movementsStartedWith = session;
        _deployments.listenToDeployments();
      }

      // The directory is behind the same gate as the Users screen. Accounts
      // that may not manage users never start it.
      if (_manager) _users.listenToUsers();

      if (needsRequests) _requests.listenToRequests();
    } catch (error) {
      // A provider disposed during sign-out refuses to start; the question
      // then gets the "could not be loaded" notes rather than an exception.
      debugPrint(
        'Local AI context: a listener could not be started '
        '(${error.runtimeType}).',
      );
    }
  }

  bool _settled({required bool needsRequests}) {
    if (AssetScope.isSettling(users: _users, assets: _assets)) return false;
    if (_bazaars.isLoading || _deployments.isLoading) return false;
    if (_manager && _users.isLoading) return false;
    if (needsRequests && _requests.isLoading) return false;
    return true;
  }

  /// Polls [ready] until it holds or the settle timeout, counted by [watch]
  /// from the start of the question, passes. Bounded on purpose, like the
  /// panel's wait: a slow stream is reported, not waited on forever.
  Future<void> _waitUntil(bool Function() ready, Stopwatch watch) async {
    if (ready()) return;

    while (watch.elapsed < _settleTimeout) {
      await Future<void>.delayed(_pollInterval);
      if (ready()) return;
    }
  }

  /// Whether the inventory listener is streaming the scope this role calls
  /// for. Right after a role change it can still be streaming the old one.
  bool _inventoryInScope() {
    if (_users.isSuperAdmin || _users.isAdmin) return !_assets.isUserScoped;

    // A User reads the whole organisation's inventory, read-only, exactly as
    // the Assets screen and the Dashboard do (see AssetScope and the
    // /assets read rule). So the only wrong scope for a User is an
    // Admin-scoped stream left over from a role change a moment ago.
    return !_assets.isUserScoped;
  }
}
