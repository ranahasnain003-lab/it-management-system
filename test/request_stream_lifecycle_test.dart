import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:it_management_system/core/services/request_service.dart';
import 'package:it_management_system/models/request_model.dart';

/// Minimal signed-in account: RequestService only reads `uid`.
class _SignedInUser implements User {
  _SignedInUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedInAuth implements FirebaseAuth {
  _SignedInAuth(this.currentUser);

  @override
  final User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const uid = 'user-a';

  late FakeFirebaseFirestore db;
  late RequestService service;

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = RequestService(firestore: db, auth: _SignedInAuth(_SignedInUser(uid)));

    // The account's profile read fails, as it does for a session that has
    // just been signed out (permission-denied).
    whenCalling(Invocation.method(#get, null))
        .on(db.collection('users').doc(uid))
        .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
  });

  test('a role lookup failing after the listener is cancelled is not an uncaught error', () async {
    final uncaught = <Object>[];

    await runZonedGuarded(() async {
      final subscription = service.getRequests().listen((_) {}, onError: (_) {});

      // Logout / account switch cancels the listener while the lookup is
      // pending. Cancelling must complete promptly (it previously hung).
      await subscription.cancel().timeout(const Duration(seconds: 2));

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });

  test('while subscribed, a failing role lookup reaches onError', () async {
    final errors = <Object>[];
    final done = Completer<void>();

    final subscription = service.getRequests().listen(
      (List<RequestModel> _) {},
      onError: (Object error) {
        errors.add(error);
        if (!done.isCompleted) done.complete();
      },
    );

    await done.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();

    expect(errors.single, isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied'));
  });
}
