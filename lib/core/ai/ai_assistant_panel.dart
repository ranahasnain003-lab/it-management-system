import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/asset_provider.dart';
import '../providers/asset_scope.dart';
import '../providers/bazaar_provider.dart';
import '../providers/deployment_provider.dart';
import '../providers/user_provider.dart';
import '../services/permission_service.dart';
import '../theme/colors.dart';
import 'action_executor.dart';
import 'action_planner.dart';
import 'ai_backend.dart';
import 'assistant_actions.dart';
import 'assistant_modal_observer.dart';
import 'inventory_assistant.dart';

/// Re-exported so existing imports of this file keep working.
export 'assistant_modal_observer.dart';

/// Wraps the app so the assistant button floats above every signed-in screen.
/// It adds nothing to the layout of the screens themselves.
class AiAssistantOverlay extends StatefulWidget {
  const AiAssistantOverlay({super.key, required this.child, this.backend});

  final Widget child;

  /// The natural-language backend. Defaults to the real one, which is itself
  /// disabled unless the build was made with AI_LLM_ENABLED=true. Tests pass a
  /// fake here to drive the whole conversation without a network.
  final AssistantBackend? backend;

  @override
  State<AiAssistantOverlay> createState() => _AiAssistantOverlayState();
}

class _AiAssistantOverlayState extends State<AiAssistantOverlay> {
  bool _open = false;

  /// This sits above the router, so there is no Navigator here to push a sheet
  /// onto: the panel is drawn in this stack instead.
  void _openPanel() {
    // The assistant can be opened from any signed-in screen, including ones
    // that never start the inventory stream (Profile, Settings, Notifications,
    // or a cold start straight into a deep link). Starting the same
    // role-scoped listener the Dashboard and Assets screens use means the
    // assistant always has the account's real inventory, and never mistakes
    // "not loaded here" for "you have none".
    AssetScope.listenFromContext(context);

    // The Bazaar list and movement records drive the Bazaar answers, and on
    // Android nothing else starts them. All three calls are safe to repeat.
    context.read<BazaarProvider>().listenToBazaars();
    context.read<DeploymentProvider>().listenToDeployments();

    // "Assign this to Ayesha" needs the same people list the Users screen
    // shows, behind the same permission gate. Accounts that may not manage
    // users never start it, and the assistant then asks instead of guessing.
    final users = context.read<UserProvider>();
    if (users.canManageUsers) users.listenToUsers();

    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    // The assistant is a mobile feature; the web build keeps its own shell.
    if (kIsWeb) return widget.child;

    final users = context.watch<UserProvider>();
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final ready = signedIn && users.hasLoadedCurrentUser && users.currentUserProfile != null;

    if (!ready && _open) {
      // The account was signed out or rejected while the panel was open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _open = false);
      });
    }

    return Stack(
      children: [
        widget.child,
        if (ready && _open)
          Positioned.fill(
            child: _AssistantSurface(
              onClose: () => setState(() => _open = false),
              backend: widget.backend,
            ),
          ),
        if (ready && !_open)
          Positioned(
            right: 16,
            bottom: 88,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: assistantModalObserver.obscured,
                builder: (context, child) {
                  // A bottom sheet, a menu or the navigation drawer is up:
                  // leave the screen to it.
                  if (assistantModalObserver.isObscured) {
                    return const SizedBox.shrink();
                  }
                  return child!;
                },
                child: _AssistantButton(onTap: _openPanel),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dimmed backdrop plus the panel, drawn without a Navigator.
class _AssistantSurface extends StatelessWidget {
  const _AssistantSurface({required this.onClose, this.backend});

  final VoidCallback onClose;
  final AssistantBackend? backend;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            type: MaterialType.transparency,
            child: _AssistantPanel(onClose: onClose, backend: backend),
          ),
        ),
      ],
    );
  }
}

/// Whether a plan from the keyword planner should be acted on as it stands.
///
/// The planner matches verbs on substrings and has no grammar, so it claims
/// plenty of messages that were never instructions. With a language model
/// available, only an unambiguous command is acted on here; everything else
/// goes to the model, which is what it is for. With no model, the planner is
/// all there is and behaves exactly as it did before the model was added.
///
/// Nothing is lost by deferring. A message that really was a command comes
/// back from the model as an intent, and ActionPlanner.planFromIntent runs it
/// through this same planner to the same conclusion, with the same checks.
bool shouldActOnPlan(
  ActionPlan plan, {
  required bool modelAvailable,
  required String message,
}) {
  // No model: the planner is all there is, and it behaves exactly as it did
  // before the model was added.
  if (!modelAvailable) return true;

  // Anything that reads as a question goes to the model, whatever the planner
  // made of it. The verb list matches on substrings, so "is IT-LAP-001
  // assigned to Ayesha Khan?" resolves into a complete, confirmable
  // assignment, and "Township Bazaar ka poora stock dikhao" into a navigation
  // that closes the panel - both of them answers to a question nobody asked.
  // Nothing is lost by deferring: a message that really was an instruction
  // comes back from the model as an intent and is planned by this same code.
  if (ActionPlanner.readsAsQuestion(message)) return false;

  // Otherwise a finished plan is acted on, and a half-understood one - which
  // is where the keyword verbs give their "which asset do you mean?" - is
  // left to the model.
  return plan.isProposal;
}

/// What the signed-in account may do, read from its live profile.
///
/// This decides only what the assistant will offer to do. The services and
/// firestore.rules remain the real enforcement, unchanged: an action that slips
/// past this check is still refused by them, and the refusal is shown as is.
AssistantPermissions buildAssistantPermissions(BuildContext context) {
  final users = context.read<UserProvider>();
  final profile = users.currentUserProfile;

  if (profile == null) return AssistantPermissions.none;

  return AssistantPermissions(
    role: users.currentUserRole,
    uid: users.currentUserUid ?? '',
    displayName: profile.name,
    roles: profile.roles,
  );
}

/// Builds everything the assistant may talk about from the providers the
/// signed-in account already uses, so its answers inherit that account's
/// permissions exactly.
InventorySnapshot buildInventorySnapshot(BuildContext context) {
  final assets = context.read<AssetProvider>();
  final bazaars = context.read<BazaarProvider>();
  final movements = context.read<DeploymentProvider>();
  final users = context.read<UserProvider>();

  final role = users.currentUserRole;

  final scope = users.isSuperAdmin || users.isAdmin
      ? ''
      : 'These figures cover the inventory of the Admin your account belongs to.';

  return InventorySnapshot(
    assets: assets.assets,
    bazaars: bazaars.bazaars,
    deployments: movements.deployments,
    totalQuantity: assets.totalQuantity,
    headOfficeStock: assets.headOfficeStock,
    assignedQuantity: assets.assignedQuantity,
    bazaarQuantity: assets.deployedToBazaarsQuantity,
    damagedQuantity: assets.damagedQuantity,
    underRepairQuantity: assets.underRepairQuantity,
    lostQuantity: assets.lostQuantity,
    disposedQuantity: assets.disposedQuantity,
    unavailableAtHeadOffice: assets.unavailableAtHeadOfficeQuantity,
    totalInventoryValue: assets.totalInventoryValue,
    roleLabel: PermissionService.roleLabel(role),
    scopeNote: scope,
    // Without these the Bazaar figures would read as a confident zero.
    bazaarDataLoaded: movements.deployments.isNotEmpty || bazaars.bazaars.isNotEmpty,
    // Separates "this account owns nothing" from "the stream has not answered
    // yet". Only the first is a real answer.
    inventoryLoading: AssetScope.isSettling(users: users, assets: assets),
    // Display names for the accounts this user can already see under Users, so
    // "who has IT-LAP-001" can be answered. Account ids and email addresses
    // stay in the app: InventorySnapshot.toFacts never emits either.
    holders: {
      for (final person in users.users)
        if (person.uid.trim().isNotEmpty && person.name.trim().isNotEmpty)
          person.uid: person.name,
    },
  );
}

// =============================================================================
// FLOATING BUTTON
// =============================================================================

class _AssistantButton extends StatefulWidget {
  const _AssistantButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AssistantButton> createState() => _AssistantButtonState();
}

class _AssistantButtonState extends State<_AssistantButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  bool _pressed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedScale(
      scale: _pressed ? 0.94 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    size: const Size(22, 22),
                    painter: _SparkPainter(
                      color: colors.onPrimary,
                      pulse: _controller.value,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A four-point sparkle with a small companion star; the companion fades in
/// and out so the button feels alive without animating the whole control.
class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.color, required this.pulse});

  final Color color;
  final double pulse;

  Path _star(Offset c, double r, double waist) {
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + waist, c.dy - waist, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + waist, c.dy + waist, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - waist, c.dy + waist, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - waist, c.dy - waist, c.dx, c.dy - r)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final main = Paint()..color = color;
    final big = size.width * 0.40;

    canvas.drawPath(
      _star(Offset(size.width * 0.44, size.height * 0.52), big, big * 0.30),
      main,
    );

    final small = Paint()..color = color.withValues(alpha: 0.55 + 0.45 * pulse);
    final r = size.width * 0.17 * (0.85 + 0.25 * pulse);

    canvas.drawPath(
      _star(Offset(size.width * 0.84, size.height * 0.22), r, r * 0.30),
      small,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.pulse != pulse || old.color != color;
}

// =============================================================================
// CHAT PANEL
// =============================================================================

class _Message {
  const _Message(this.text, {required this.fromUser});

  final String text;
  final bool fromUser;
}

class _AssistantPanel extends StatefulWidget {
  const _AssistantPanel({required this.onClose, this.backend});

  final VoidCallback onClose;
  final AssistantBackend? backend;

  @override
  State<_AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<_AssistantPanel> {
  final _assistant = InventoryAssistant();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  late final _planner = ActionPlanner(finder: _assistant);
  late final AssistantBackend _backend = widget.backend ?? const AiBackend();
  final _executor = ActionExecutor();

  /// A change the user has been shown and has not answered yet. Nothing is
  /// written while this is set: it waits for Confirm or Cancel.
  AssistantAction? _pending;

  /// True while a confirmed action is being carried out.
  bool _running = false;

  final List<_Message> _messages = [
    const _Message(
      'Hello. Ask me anything about the inventory, in your own words - '
      'English, Urdu or Roman Urdu. For example "how many laptops do we '
      'have?", "head office mein kitne hain" or an Asset ID.',
      fromUser: false,
    ),
  ];

  bool _thinking = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Waits, briefly, for the account's inventory stream to deliver.
  ///
  /// Bounded on purpose: if the stream is slow or has failed, the assistant
  /// still answers rather than hanging, and [InventorySnapshot.inventoryLoading]
  /// lets it say "still loading" instead of "you have none".
  Future<void> _waitForInventory() async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));

    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;

      final settling = AssetScope.isSettling(
        users: context.read<UserProvider>(),
        assets: context.read<AssetProvider>(),
      );

      if (!settling) return;

      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  /// Deals with a planned action.
  ///
  /// Returns the text to show, or null to fall through to the ordinary
  /// read-only answer. Nothing is written here: a proposal is only put on
  /// screen, and [_confirm] is the single place that carries one out.
  Future<String?> _handlePlan(
    ActionPlan plan,
    String question,
    InventorySnapshot snapshot,
    List<Map<String, dynamic>> history, {
    bool reword = true,
  }) async {
    // A question the assistant needs answered, or a refusal. Either way this
    // is plain, grounded text; the model may reword it but cannot change it.
    //
    // [reword] is false when this plan came from the model's own reading of
    // the message. It has already spoken, in the user's own language, and a
    // second call for the same question would spend another request against
    // the daily cap and be refused by the burst interval anyway - which the
    // user would see as a spurious "please wait a moment".
    if (!plan.isProposal) {
      return reword
          ? await _worded(question, plan.message, snapshot, history)
          : plan.message;
    }

    final action = plan.action!;

    // Opening a screen writes nothing, so it needs no confirmation.
    if (!action.writes) {
      if (mounted) {
        widget.onClose();
        GoRouter.of(context).go(action.route);
      }
      return null;
    }

    setState(() => _pending = action);

    final preview = StringBuffer(action.title)..writeln();
    for (final line in action.details) {
      preview.writeln('  $line');
    }
    preview.write(
      action.viaRequest
          ? '\nTap "Send request" to submit it, or Cancel.'
          : '\nTap Confirm to make this change, or Cancel.',
    );

    // Deliberately not sent to the language model: a preview the user is about
    // to approve must say exactly what will happen, word for word.
    return preview.toString();
  }

  /// Runs [text] through the language model for natural wording, falling back
  /// to [text] itself whenever the backend is unavailable or over its limit.
  Future<String> _worded(
    String question,
    String text,
    InventorySnapshot snapshot,
    List<Map<String, dynamic>> history,
  ) async {
    String? limitNotice;

    // Wording only. Any action the model suggests in reply is ignored here on
    // purpose: the app has already decided what this message was, and a
    // question or a refusal is not the place to reopen that.
    final worded = await _backend.ask(
      question: question,
      facts: snapshot.toFacts(),
      groundedAnswer: text,
      history: history,
      onLimited: (notice) => limitNotice = notice,
    );

    final answer = worded?.text ?? text;
    final notice = limitNotice;

    return notice == null ? answer : '$answer\n\n$notice';
  }

  /// Carries out the proposed change. The only place in the assistant that
  /// writes anything, and it is reached only by the user tapping Confirm.
  Future<void> _confirm() async {
    final action = _pending;
    if (action == null || _running) return;

    setState(() {
      _running = true;
      _thinking = true;
    });
    _scrollToEnd();

    // Both flags above gate _send(). If anything below threw they would stay
    // set for good, and from then on every question the user typed would be
    // dropped in silence - no new bubble, no error, the previous answer just
    // sitting there. So the outcome is resolved defensively and the flags are
    // always cleared.
    var message = 'That did not go through. Nothing was changed.';

    try {
      final permissions = buildAssistantPermissions(context);

      // Bounded, because a Firestore write made with no connection does not
      // fail - it is queued, and its Future simply never completes until the
      // server acknowledges it. Without this the two flags above would stay
      // set for the life of the panel and every later question would be
      // dropped in silence, which is the exact failure this method was
      // already written to avoid.
      final result =
          await _executor.run(action, permissions).timeout(_actionTimeout);

      message = result.message;
    } on TimeoutException {
      // A queued write can still land later, so "nothing was changed" would
      // be a guess, and the wrong one.
      message = 'That is taking longer than usual. It may still go through, '
          'so check the record before trying it again.';
    } catch (error) {
      debugPrint('Assistant could not carry that out: $error');
    }

    if (!mounted) return;

    setState(() {
      _pending = null;
      _running = false;
      _thinking = false;
      _messages.add(_Message(message, fromUser: false));
    });
    _scrollToEnd();

    // The change is already in Firestore; the streams the app listens to push
    // the new figures back on their own.
  }

  void _cancel() {
    if (_running) return;

    setState(() {
      _pending = null;
      _messages.add(
        const _Message('Cancelled. Nothing was changed.', fromUser: false),
      );
    });
    _scrollToEnd();
  }

  /// How long a confirmed change is waited on before the user is told it is
  /// taking too long. See [_confirm].
  static const Duration _actionTimeout = Duration(seconds: 20);

  /// Email addresses, as they appear in text bound for the backend.
  static final RegExp _address = RegExp(r'\s*\(?[\w.+-]+@[\w-]+\.[\w.-]+\)?');

  /// Strips email addresses out of text before it leaves the app.
  ///
  /// The confirmation preview deliberately names a person as "Ayesha Khan
  /// (ayesha@test.local)", so that the user approves the right account. That
  /// bubble then becomes part of the conversation, and the conversation is
  /// sent to the model as context - so without this the address would travel
  /// with it, which is exactly what InventorySnapshot.toFacts takes care never
  /// to do. The name is what the model needs to follow the thread; the address
  /// is not.
  static String _withoutAddresses(String text) =>
      text.replaceAll(_address, '');

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _thinking || _running) return;

    // A proposal that has not been answered is dropped: typing something else
    // is as clear a "no" as tapping Cancel, and nothing has been written.
    if (_pending != null) setState(() => _pending = null);

    final recent = _messages
        .skip(_messages.length > 6 ? _messages.length - 6 : 0)
        .map((m) => {'fromUser': m.fromUser, 'text': _withoutAddresses(m.text)})
        .toList();

    setState(() {
      _messages.add(_Message(question, fromUser: true));
      _thinking = true;
      _input.clear();
    });
    _scrollToEnd();

    // The facts and the answer are computed here, from data already in memory
    // and already filtered by this account's permissions. Nothing below may
    // leave the panel stuck on the typing indicator.
    var answer = 'Something went wrong while reading the inventory. '
        'Please close the assistant and try again.';

    try {
      // Opening the panel starts the account's inventory listener. A question
      // asked in the moment right after would otherwise be answered from an
      // empty list, which is how the assistant used to claim it could see no
      // inventory on an account that plainly had some.
      await _waitForInventory();

      if (!mounted) return;

      final snapshot = buildInventorySnapshot(context);
      final permissions = buildAssistantPermissions(context);
      final people = context.read<UserProvider>().users;

      // Is this an instruction rather than a question? The planner resolves it
      // against this same permission-scoped snapshot, so it can only ever name
      // an asset, Bazaar, person or figure the account can already see. It
      // returns null for ordinary questions, which stay read-only.
      final plan = _planner.plan(
        question,
        snapshot,
        permissions,
        people: people,
        lastAsset: _assistant.lastAsset,
      );

      // A fully formed command is acted on here and now: the planner is
      // deterministic, costs nothing and works with no network.
      //
      // A half-understood one is NOT. The verb list fires on ordinary
      // questions too - "what was moved to Township last week?" and "is
      // IT-LAP-001 assigned to anyone?" both read as commands - and answering
      // those with "which asset do you mean?" is exactly the fixed-keyword
      // behaviour the model is here to replace. So an ask or a refusal is
      // handed on to the model when there is one, and only stands on its own
      // when there is not. Nothing is lost by doing so: if the message really
      // was a command, the model says so and planFromIntent runs it back
      // through this same planner, which reaches the same conclusion.
      if (plan != null &&
          shouldActOnPlan(
            plan,
            modelAvailable: _backend.enabled,
            message: question,
          )) {
        final outcome = await _handlePlan(plan, question, snapshot, recent);
        if (outcome != null) {
          if (!mounted) return;
          setState(() {
            _messages.add(_Message(outcome, fromUser: false));
            _thinking = false;
          });
          _scrollToEnd();
          return;
        }

        // Nothing to say means the plan was a navigation: the panel has been
        // closed and the route has already changed. Carrying on would compute
        // an answer nobody is there to read, and spend one of the account's
        // model requests doing it.
        if (!mounted) return;
        setState(() => _thinking = false);
        return;
      }

      // The deterministic engine always runs. Its answer is what the user sees
      // when the model is switched off or unreachable, and it is the
      // authoritative figure handed to the model when it is on - but only when
      // it actually recognised the question, because its "ask me another way"
      // message answers nothing and must not be passed off as an answer.
      final reply = _assistant.answer(question, snapshot);
      answer = reply.text;

      // Set when the backend refuses the call because this account has used
      // its allowance. The answer below is still correct - only the wording
      // step was skipped - so the note is appended rather than shown alone.
      String? limitNotice;

      // Natural language, in the user's own words and their own script. The
      // model is given nothing but this account's own permission-scoped facts,
      // and it can write nothing. If it is unavailable, disabled or over its
      // limit, the computed answer above is shown unchanged and the assistant
      // simply keeps working.
      final understood = await _backend.ask(
        // Redacted like the history is. The planner's own wording asks for
        // "the exact name or the email address", so an address genuinely
        // turns up here - and toFacts never sends one, which would make this
        // the only way a colleague's address reached the model.
        question: _withoutAddresses(question),
        facts: snapshot.toFacts(focus: reply.asset),
        groundedAnswer: reply.understood ? reply.text : '',
        history: recent,
        capabilities: permissions.assistantCapabilities,
        onLimited: (notice) => limitNotice = notice,
      );

      if (understood != null) {
        // The model may have read the message as an instruction rather than a
        // question. Its reading is only a hint: every name, number and
        // permission in it is resolved and checked again from scratch against
        // this same snapshot, and a change still has to be confirmed.
        // A question back to the user is a question, not a change. The model
        // sets this when it could not tell which asset, Bazaar or person was
        // meant, and acting on the half-formed reading it also returned would
        // turn "which Bazaar did you mean?" into a one-tap confirmation.
        final intent = understood.needsClarification ? null : understood.intent;

        if (intent != null) {
          final intentPlan = _planner.planFromIntent(
            intent,
            snapshot,
            permissions,
            people: people,
          );

          if (intentPlan != null && intentPlan.isProposal) {
            final outcome = await _handlePlan(
              intentPlan,
              question,
              snapshot,
              recent,
              reword: false,
            );
            if (outcome != null) {
              if (!mounted) return;
              setState(() {
                _messages.add(_Message(outcome, fromUser: false));
                _thinking = false;
              });
              _scrollToEnd();
              return;
            }
          }

          // The planner would not put that change up. Its refusal names a
          // real rule - a permission, a stock figure - so the user has to
          // hear it; but it is in English, and the model has already answered
          // in the language they wrote in. So the refusal is added to that
          // answer rather than replacing it. A mere request for clarification
          // is dropped entirely: the model's own words are the better version
          // of the same thing.
          final refusal = intentPlan?.refusal;
          answer = refusal == null
              ? understood.text
              : '${understood.text}\n\n$refusal';
        } else {
          answer = understood.text;
        }
      }

      final notice = limitNotice;
      if (notice != null) answer = '$answer\n\n$notice';
    } catch (error) {
      debugPrint('Assistant could not answer: $error');
    }

    if (!mounted) return;

    setState(() {
      _messages.add(_Message(answer, fromUser: false));
      _thinking = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scroll.hasClients) return;

      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );

      // The list builds its bubbles lazily, so a long answer - a Bazaar
      // breakdown, the help text - can still be laying out when the extent
      // above is measured, and the trip stops short with the newest answer
      // below the fold. That reads as "it gave me the same answer again", so
      // the end is measured once more after the frame has settled.
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.offset < end) _scroll.jumpTo(end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);

    // The panel sits above the keyboard, so it can only use the height the
    // keyboard and the status bar leave behind. Sizing it against the FULL
    // screen height meant that with the keyboard open the panel was taller
    // than the space it had: it overflowed upwards, carrying its header - and
    // with it the only Close button - above the top of the screen, while
    // covering the scrim that would otherwise have dismissed it.
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.top;

    final preferred = (media.size.height * 0.82).clamp(340.0, 760.0);
    final height = preferred > available ? available : preferred;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: height),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(context),
                Divider(height: 1, color: colors.outlineVariant),
                Flexible(child: _messageList(context)),
                if (_pending != null) _confirmBar(context, _pending!),
                _composer(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.tint(colors.primary, Theme.of(context).brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: CustomPaint(
              size: const Size(20, 20),
              painter: _SparkPainter(color: colors.primary, pulse: 1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  'Answers from your live inventory',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _messageList(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      itemCount: _messages.length + (_thinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return const _TypingBubble();
        return _Bubble(message: _messages[index]);
      },
    );
  }

  /// The confirmation strip. Nothing is written until Confirm is tapped here.
  Widget _confirmBar(BuildContext context, AssistantAction action) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, Theme.of(context).brightness),
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _running ? null : _cancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _running ? null : _confirm,
                child: _running
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(action.confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Ask about stock, a Bazaar or an Asset ID...',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 46,
              width: 46,
              child: Material(
                color: colors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _thinking ? null : _send,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: colors.onPrimary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mine = message.fromUser;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine
              ? colors.primary
              : AppColors.tint(colors.primary, Theme.of(context).brightness),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: mine
                ? colors.onPrimary
                : AppColors.onTint(colors.primary, Theme.of(context).brightness),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tone = AppColors.onTint(colors.primary, Theme.of(context).brightness);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.tint(colors.primary, Theme.of(context).brightness),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_controller.value + i * 0.22) % 1;
                final lift = (t < 0.5 ? t : 1 - t) * 2;

                return Padding(
                  padding: EdgeInsets.only(
                    right: i == 2 ? 0 : 5,
                    bottom: 3 * lift,
                  ),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.45 + 0.45 * lift),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
