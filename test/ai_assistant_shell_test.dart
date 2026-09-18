import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/ai_assistant_panel.dart';
import 'package:it_management_system/core/ai/ai_backend.dart';

/// Lets the tests build the exception the Cloud Function throws. The real
/// constructor is protected, so it is reached through a subclass.
class _FunctionsError extends FirebaseFunctionsException {
  _FunctionsError({required super.code, required super.message});
}

/// A minimal modal route, to check the observer reacts to the type rather
/// than to any one Material widget.
class _FakeModalRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const SizedBox.shrink();
  }
}

void main() {
  // =========================================================================
  // MODAL OBSERVER
  //
  // The assistant now lives in the router's signed-in shell, so dialogs (root
  // navigator) are drawn above it. Bottom sheets open on the shell navigator
  // instead, and this observer is what takes the button out of their way.
  // =========================================================================

  group('AssistantModalObserver', () {
    test('starts with no modal open', () {
      expect(AssistantModalObserver().openModals.value, 0);
      expect(assistantModalObserver.openModals.value, 0);
    });

    test('ignores ordinary page routes', () {
      final observer = AssistantModalObserver();
      final page = MaterialPageRoute<void>(builder: (_) => const SizedBox());

      observer.didPush(page, null);
      expect(observer.openModals.value, 0);

      observer.didPop(page, null);
      expect(observer.openModals.value, 0);
    });

    test('counts modal routes as they open and close', () {
      final observer = AssistantModalObserver();
      final first = _FakeModalRoute();
      final second = _FakeModalRoute();

      observer.didPush(first, null);
      expect(observer.openModals.value, 1);

      observer.didPush(second, first);
      expect(observer.openModals.value, 2);

      observer.didPop(second, first);
      expect(observer.openModals.value, 1);

      observer.didRemove(first, null);
      expect(observer.openModals.value, 0);
    });

    test('never falls below zero on an unmatched pop', () {
      final observer = AssistantModalObserver();

      observer.didPop(_FakeModalRoute(), null);
      observer.didRemove(_FakeModalRoute(), null);

      expect(observer.openModals.value, 0);
    });

    test('an open navigation drawer obscures the button', () {
      final observer = AssistantModalObserver();

      expect(observer.isObscured, isFalse);

      observer.setDrawerOpen(true);
      expect(observer.isObscured, isTrue);

      observer.setDrawerOpen(false);
      expect(observer.isObscured, isFalse);
    });

    test('a drawer and a sheet together clear only when both are gone', () {
      final observer = AssistantModalObserver();
      final sheet = _FakeModalRoute();

      observer.setDrawerOpen(true);
      observer.didPush(sheet, null);
      expect(observer.isObscured, isTrue);

      observer.didPop(sheet, null);
      expect(observer.isObscured, isTrue, reason: 'the drawer is still open');

      observer.setDrawerOpen(false);
      expect(observer.isObscured, isFalse);
    });

    test('the merged signal notifies for either source', () {
      final observer = AssistantModalObserver();
      var notifications = 0;

      observer.obscured.addListener(() => notifications++);

      observer.setDrawerOpen(true);
      expect(notifications, 1);

      observer.didPush(_FakeModalRoute(), null);
      expect(notifications, 2);
    });

    test('a replaced modal is counted once', () {
      final observer = AssistantModalObserver();
      final old = _FakeModalRoute();

      observer.didPush(old, null);
      observer.didReplace(newRoute: _FakeModalRoute(), oldRoute: old);

      expect(observer.openModals.value, 1);
    });

    test('replacing a modal with a page route clears the count', () {
      final observer = AssistantModalObserver();
      final old = _FakeModalRoute();

      observer.didPush(old, null);
      observer.didReplace(
        newRoute: MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        oldRoute: old,
      );

      expect(observer.openModals.value, 0);
    });
  });

  testWidgets('the assistant button steps aside while a bottom sheet is open',
      (tester) async {
    final observer = AssistantModalObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: Stack(
              children: [
                Center(
                  child: ElevatedButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => const SizedBox(height: 160),
                    ),
                    child: const Text('Open sheet'),
                  ),
                ),
                // Stands in for the floating assistant button, driven by the
                // same notifier the shell uses.
                Positioned(
                  right: 16,
                  bottom: 88,
                  child: ValueListenableBuilder<int>(
                    valueListenable: observer.openModals,
                    builder: (context, openModals, child) =>
                        openModals > 0 ? const SizedBox.shrink() : child!,
                    child: const Text('Assistant'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Assistant'), findsOneWidget);

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(observer.openModals.value, 1);
    expect(find.text('Assistant'), findsNothing);

    // Dismiss by tapping the barrier above the sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(observer.openModals.value, 0);
    expect(find.text('Assistant'), findsOneWidget);
  });

  // =========================================================================
  // DAILY CAP FEEDBACK
  //
  // The cap itself is enforced in the Cloud Function (functions/usage_policy.js,
  // covered by functions/test). These tests cover what the app does with the
  // refusal: it tells the user, and it still shows the answer it computed.
  // =========================================================================

  // =========================================================================
  // FREE / LOCAL MODE
  //
  // The app must work fully with no paid AI dependency. These tests fail if a
  // build ever ships that would reach for the Cloud Function by default.
  // =========================================================================

  group('the assistant is free by default', () {
    test('the language model is disabled unless a build opts in', () {
      expect(
        AiBackend.isEnabled,
        isFalse,
        reason: 'shipping with the model on would make the app depend on a '
            'deployed, billed Cloud Function',
      );
    });

    test('rephrase returns null without touching Firebase at all', () async {
      // Firebase is not initialised in this test. If rephrase attempted the
      // call it would throw [core/no-app]; returning null proves the paid path
      // is never entered.
      final worded = await const AiBackend().rephrase(
        question: 'total stock',
        facts: const {'totals': {}},
        groundedAnswer: 'Inventory overview',
      );

      expect(worded, isNull);
    });

    test('a disabled model never reports a quota notice', () async {
      var notified = false;

      await const AiBackend().rephrase(
        question: 'total stock',
        facts: const {},
        groundedAnswer: 'Inventory overview',
        onLimited: (_) => notified = true,
      );

      expect(notified, isFalse);
    });
  });

  group('AiBackend.quotaNotice', () {
    test('returns the backend message when the account hit its limit', () {
      final notice = AiBackend.quotaNotice(
        _FunctionsError(
          code: 'resource-exhausted',
          message: "You have reached today's limit of 60 assistant questions.",
        ),
      );

      expect(notice, "You have reached today's limit of 60 assistant questions.");
    });

    test('falls back to its own wording when the message is empty', () {
      final notice = AiBackend.quotaNotice(
        _FunctionsError(code: 'resource-exhausted', message: '   '),
      );

      expect(notice, isNotNull);
      expect(notice, contains('limit'));
    });

    test('stays silent for every other backend failure', () {
      expect(
        AiBackend.quotaNotice(
          _FunctionsError(code: 'unavailable', message: 'busy'),
        ),
        isNull,
      );
      expect(
        AiBackend.quotaNotice(
          _FunctionsError(code: 'not-found', message: 'not deployed'),
        ),
        isNull,
      );
      expect(
        AiBackend.quotaNotice(
          _FunctionsError(
            code: 'failed-precondition',
            message: 'This request did not come from a recognised app installation.',
          ),
        ),
        isNull,
      );
      expect(AiBackend.quotaNotice(Exception('offline')), isNull);
      expect(AiBackend.quotaNotice('some string'), isNull);
    });
  });
}
