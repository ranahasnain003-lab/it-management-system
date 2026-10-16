/// Tests for [BazaarService.createBazaar], in particular the duplicate-name
/// guard inside its Firestore transaction.
///
/// That guard used to run through a raw `firestore.runTransaction(...)`. On
/// Flutter Web, an exception thrown inside a transaction callback does not
/// survive the JS-interop round trip back into the Dart Future cleanly - it
/// surfaces to the caller as an opaque "Dart exception thrown from converted
/// Future", with the real message ("A Bazaar with this name already
/// exists.") lost. `createBazaar` now goes through `runGuardedTransaction`,
/// the same helper every other service's transaction already uses, which
/// catches the error inside the callback and rethrows it afterwards as a
/// plain Dart exception instead of letting it escape through the promise.
///
/// `fake_cloud_firestore` cannot reproduce the web JS-interop bug itself -
/// it is a pure-Dart fake with no JS boundary - so what this file proves is
/// the contract the fix depends on: the duplicate-name error, thrown from
/// inside the transaction, reaches the caller with its real message intact.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/services/bazaar_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late BazaarService bazaars;

  setUp(() {
    db = FakeFirebaseFirestore();
    bazaars = BazaarService(firestore: db);
  });

  group('createBazaar', () {
    test('writes a new Bazaar at a deterministic id', () async {
      final id = await bazaars.createBazaar(
        name: 'Township Bazaar',
        location: 'Lahore',
        createdBy: 'uid-1',
        createdByName: 'Admin',
      );

      expect(id, 'bz_township_bazaar');

      final doc = await db.collection('bazaars').doc(id).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['name'], 'Township Bazaar');
    });

    test(
      'a duplicate name is refused with its real message, not a boxed one',
      () async {
        await bazaars.createBazaar(
          name: 'Township Bazaar',
          location: 'Lahore',
          createdBy: 'uid-1',
          createdByName: 'Admin',
        );

        // This is the pre-check (_assertNameIsFree), run before the
        // transaction even starts.
        await expectLater(
          bazaars.createBazaar(
            name: 'Township Bazaar',
            location: 'Lahore',
            createdBy: 'uid-2',
            createdByName: 'Someone Else',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('A Bazaar with this name already exists.'),
            ),
          ),
        );
      },
    );

    test(
      'the transaction\'s own duplicate check is refused with its real '
      'message too, not the pre-check\'s',
      () async {
        // A document already sits at the exact id this name would produce,
        // but under a DIFFERENT name - so the whole-collection pre-check
        // (which matches by name) does not see it as a duplicate, and only
        // the transaction's own `existing.exists` read catches it. This is
        // the one path that used to go through a raw runTransaction and lose
        // its error message on web.
        await db.collection('bazaars').doc('bz_township_bazaar').set({
          'name': 'Some Other Bazaar Entirely',
          'location': 'Multan',
          'isActive': true,
        });

        await expectLater(
          bazaars.createBazaar(
            name: 'Township Bazaar',
            location: 'Lahore',
            createdBy: 'uid-1',
            createdByName: 'Admin',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('A Bazaar with this name already exists.'),
            ),
          ),
        );

        // And the pre-existing document was not overwritten.
        final doc = await db.collection('bazaars').doc('bz_township_bazaar').get();
        expect(doc.data()!['name'], 'Some Other Bazaar Entirely');
      },
    );

    test('an empty name is refused before any Firestore call', () async {
      await expectLater(
        bazaars.createBazaar(name: '   '),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Bazaar name is required.'),
          ),
        ),
      );
    });

    test('punctuation and spacing differences still collide', () async {
      await bazaars.createBazaar(
        name: 'Township Bazaar',
        location: 'Lahore',
        createdBy: 'uid-1',
        createdByName: 'Admin',
      );

      await expectLater(
        bazaars.createBazaar(
          name: 'township-bazaar',
          location: 'Lahore',
          createdBy: 'uid-2',
          createdByName: 'Someone Else',
        ),
        throwsException,
      );
    });
  });
}
