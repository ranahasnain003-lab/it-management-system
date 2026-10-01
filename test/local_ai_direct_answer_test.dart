// Tests for the direct answers: the plain lookups the app answers by itself,
// from the same permission-scoped records, without asking the model.
//
// Two things matter, in this order:
//
//   * Nothing that is not a plain lookup is answered here. A reason, a
//     comparison, a command, a negation, a stray number, an unknown word, or
//     data that was not read in full, all go to the model. A wrong instant
//     answer is worse than a right slow one.
//   * What is answered here is exact: the figures the app's own screens show,
//     for exactly what the account may see.
//
// The fixtures are the ones the appContext tests use.

import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/inventory_assistant.dart';
import 'package:it_management_system/core/ai/local/local_ai_inventory_context.dart';

import 'local_ai_context_test.dart' as fx;

/// The direct answer to [question], or null when it goes to the model.
String? direct(
  String question, {
  String role = 'admin',
  String? previous,
  InventorySnapshot? snapshot,
  LocalAiSourceState inventoryState = LocalAiSourceState.ready,
  LocalAiSourceState movementState = LocalAiSourceState.ready,
  LocalAiSourceState requestState = LocalAiSourceState.ready,
  LocalAiSourceState peopleState = LocalAiSourceState.ready,
  bool inScope = true,
}) {
  return fx
      .ask(
        question,
        role: role,
        previous: previous,
        snapshot: snapshot,
        inventoryState: inventoryState,
        movementState: movementState,
        requestState: requestState,
        peopleState: peopleState,
        inScope: inScope,
      )
      .context
      .directAnswer;
}

void main() {
  // ---------------------------------------------------------------------------
  // ANSWERED BY THE APP
  // ---------------------------------------------------------------------------

  group('Plain lookups are answered by the app', () {
    test('the whole inventory, in English and Roman Urdu', () {
      const overview =
          'Inventory overview:\n'
          '• Asset records: 7\n'
          '• Total quantity: 46 units\n'
          '• Available at Head Office: 22 units\n'
          '• At Bazaars: 13 units\n'
          '• Assigned to people: 1 unit\n'
          '• Not usable at Head Office: 10 units (damaged 3, under repair 4, '
          'lost 2, disposed 1)';

      expect(direct('What is our total inventory?'), overview);
      expect(direct('How many assets do we have?'), overview);
      expect(direct('kul kitna stock hai'), overview);
    });

    test('a category, with where its units are', () {
      const laptops =
          'Laptop category: 16 units in 2 asset records - 10 at Head Office, '
          '5 at Bazaars, 1 assigned.\n'
          '• ABC-123 (Dell Latitude 5420): 10 units (Head Office 4, Bazaars 5, '
          'assigned 1)\n'
          '• LAP-002 (HP ProBook 450): 6 units (Head Office 6, Bazaars 0, '
          'assigned 0)';

      expect(direct('How many laptops do we have?'), laptops);
      expect(direct('laptops kitne hain?'), laptops);
    });

    test(
      'damaged stock is the Dashboard figure, with the records behind it',
      () {
        expect(
          direct('How many damaged assets?'),
          'Damaged: 3 units at Head Office, as the Dashboard counts them.\n'
          '1 asset record marked damaged:\n'
          '• PRN-001 (Canon Printer LBP): 3 units, 3 at Head Office',
        );
        expect(
          direct('which assets are under repair'),
          startsWith('Under repair: 4 units at Head Office'),
        );
        expect(direct('lost items'), startsWith('Lost or missing: 2 units'));
        expect(
          direct('show damaged laptops'),
          'Damaged, in the Laptop category: 0 units at Head Office.\n'
          'No asset record in the Laptop category is marked damaged.',
        );
      },
    );

    test('the headline is the snapshot\'s own figure, not a recount', () {
      // AssetProvider's figure is what the Dashboard shows. Should it ever
      // differ from a sum over the records, the answer must still match the
      // screen the person is looking at.
      final base = fx.snapshotOf(fx.inventory);
      final snapshot = InventorySnapshot(
        assets: base.assets,
        bazaars: base.bazaars,
        deployments: base.deployments,
        totalQuantity: base.totalQuantity,
        headOfficeStock: base.headOfficeStock,
        assignedQuantity: base.assignedQuantity,
        bazaarQuantity: base.bazaarQuantity,
        damagedQuantity: 9,
        underRepairQuantity: base.underRepairQuantity,
        lostQuantity: base.lostQuantity,
        disposedQuantity: base.disposedQuantity,
        unavailableAtHeadOffice: base.unavailableAtHeadOffice,
        totalInventoryValue: base.totalInventoryValue,
        roleLabel: base.roleLabel,
        scopeNote: base.scopeNote,
        holders: base.holders,
      );

      expect(
        direct('damaged assets', snapshot: snapshot),
        startsWith('Damaged: 9 units at Head Office, as the Dashboard'),
      );
    });

    test('Head Office, available and assigned stock', () {
      expect(
        direct('head office mein kitne hain'),
        'Head Office has 22 units available for use, plus 10 units that '
        'cannot be used (damaged, under repair, lost or disposed).',
      );
      expect(
        direct('How many laptops at head office?'),
        'At Head Office, in the Laptop category: 10 units, of which 10 can be '
        'used.\n'
        '• LAP-002 (HP ProBook 450): 6 units (Available)\n'
        '• ABC-123 (Dell Latitude 5420): 4 units (Available)',
      );
      expect(
        direct('available stock'),
        'Available at Head Office: 22 units, in 3 asset records.\n'
        '• MON-001 (Samsung Monitor 24): 12 units\n'
        '• LAP-002 (HP ProBook 450): 6 units\n'
        '• ABC-123 (Dell Latitude 5420): 4 units',
      );
      expect(
        direct('assigned assets'),
        'Assigned: 1 unit, in 1 asset record.\n'
        '• ABC-123 (Dell Latitude 5420): 1 unit, held by Ayesha Khan',
      );
    });

    test('one Bazaar, every Bazaar, and the Bazaar list', () {
      expect(
        direct('Township Bazaar mein kitna stock hai'),
        'Township Bazaar has 11 units, from 2 assets:\n'
        '• MON-001 (Samsung Monitor 24): 8 units\n'
        '• ABC-123 (Dell Latitude 5420): 3 units',
      );
      expect(
        direct('laptops at Township Bazaar'),
        'Township Bazaar has 3 units in the Laptop category, from 1 asset:\n'
        '• ABC-123 (Dell Latitude 5420): 3 units',
      );

      const perBazaar =
          'Stock at Bazaars: 13 units, at 2 Bazaars:\n'
          '• Township Bazaar: 11 units\n'
          '• Sahiwal Bazaar: 2 units\n'
          'With no stock: Model Town Bazaar.';
      expect(direct('bazaar stock'), perBazaar);

      // Asked which Bazaar has the most or the fewest, the answer names it
      // first and then shows the figures it came from.
      expect(
        direct('which bazaar has the most stock?'),
        'Township Bazaar has the most stock of any Bazaar: 11 units.\n$perBazaar',
      );
      expect(
        direct('which bazaar has the least stock?'),
        'Sahiwal Bazaar has the least stock of any Bazaar: 2 units.\n$perBazaar',
      );
      // Only the Bazaars that hold some of it are compared: one with none is
      // on the "with no stock" line, and is not the one with the fewest.
      expect(direct('which bazaar has the most laptops?'), contains('Township Bazaar has the most of any Bazaar, in the Laptop category: 3 units.'));
      expect(direct('which bazaar has the fewest laptops?'), contains('Sahiwal Bazaar has the least of any Bazaar, in the Laptop category: 2 units.'));

      expect(
        direct('how many bazaars are there'),
        '3 Bazaars in all: 2 active, 1 disabled.\n'
        '• Model Town Bazaar (Lahore) - disabled\n'
        '• Sahiwal Bazaar (Sahiwal)\n'
        '• Township Bazaar (Lahore)',
      );
      expect(
        direct('active bazaars in Lahore'),
        'Active Bazaars in Lahore: 1.\n• Township Bazaar (Lahore)',
      );
    });

    test(
      'one asset: details, where it is, warranty, price, holder, history',
      () {
        final card = direct('ABC-123')!;
        expect(card, startsWith('ABC-123 (Dell Latitude 5420)\n'));
        expect(card, contains('• Serial number: SN-DL-5420-01'));
        expect(
          card,
          contains(
            '• Quantity: 10 units - 4 at Head Office, 5 at Bazaars, 1 assigned',
          ),
        );
        expect(card, contains('• Warranty: ends on 2027-01-10, in 103 days.'));

        const where =
            'ABC-123 (Dell Latitude 5420) is at:\n'
            '• Head Office: 4 units\n'
            '• Township Bazaar: 3 units\n'
            '• Sahiwal Bazaar: 2 units\n'
            '• Assigned to Ayesha Khan: 1 unit';
        expect(direct('where is ABC-123?'), where);
        expect(direct('ABC-123 kahan hai'), where);

        expect(
          direct('ABC-123 ki warranty'),
          'ABC-123 (Dell Latitude 5420)\n'
          'Warranty: ends on 2027-01-10, in 103 days.',
        );
        expect(
          direct('price of ABC-123'),
          'ABC-123 (Dell Latitude 5420)\n'
          'Unit price: Rs. 150,000 · Quantity: 10 units · Total value: '
          'Rs. 1,500,000',
        );
        expect(
          direct('who has ABC-123'),
          'ABC-123 (Dell Latitude 5420): 1 unit assigned to Ayesha Khan.',
        );
        expect(
          direct('ABC-123 history'),
          'ABC-123 (Dell Latitude 5420): 3 movements. The latest:\n'
          '• 2026-09-25 · 3 units · Head Office → Township Bazaar (Active)\n'
          '• 2026-08-19 · 2 units · Head Office → Sahiwal Bazaar (Active)\n'
          '• 2026-07-30 · 2 units · Head Office → Township Bazaar (Returned)',
        );
        expect(
          direct('status of ABC-123'),
          'ABC-123 (Dell Latitude 5420): status Available, condition Good.',
        );
      },
    );

    test('"no. of" is "number of", and a verb used as a noun is a lookup', () {
      expect(
        direct('no. of laptops'),
        startsWith('Laptop category: 16 units in 2 asset records'),
      );
      expect(
        direct('transfer history of ABC-123'),
        startsWith('ABC-123 (Dell Latitude 5420): 3 movements.'),
      );
    });

    test('Urdu script the question vocabulary knows', () {
      expect(
        direct('ABC-123 کی وارنٹی'),
        'ABC-123 (Dell Latitude 5420)\n'
        'Warranty: ends on 2027-01-10, in 103 days.',
      );
    });

    test('value, and the most valuable assets', () {
      expect(
        direct('total inventory value'),
        'Total inventory value: Rs. 2,920,000, for 46 units in 7 asset '
        'records.',
      );
      expect(
        direct('value of laptops'),
        'Value in the Laptop category: Rs. 2,220,000, for 16 units in 2 asset '
        'records.',
      );
      expect(
        direct('most expensive assets'),
        'Total inventory value: Rs. 2,920,000, for 46 units in 7 asset '
        'records.\n'
        'Most valuable:\n'
        '• ABC-123 (Dell Latitude 5420): Rs. 1,500,000 (10 units)\n'
        '• LAP-002 (HP ProBook 450): Rs. 720,000 (6 units)\n'
        '• MON-001 (Samsung Monitor 24): Rs. 600,000 (20 units)\n'
        '• RTR-001 (TP-Link Router): Rs. 40,000 (4 units)\n'
        '• PRN-001 (Canon Printer LBP): Rs. 30,000 (3 units)',
      );
    });

    test('warranties, transfers and requests', () {
      expect(
        direct('which warranties are expiring'),
        'Warranty end dates are known for 1 asset record: 0 expired, 0 end '
        'within 90 days.\n'
        'Ending soonest:\n'
        '• ABC-123 (Dell Latitude 5420): ends 2027-01-10, in 103 days',
      );
      expect(
        direct('transfers in the last 7 days'),
        'Movements in the last 7 days: 1, 3 units in all:\n'
        '• 2026-09-25 · ABC-123 (Dell Latitude 5420) · 3 units · Head Office '
        '→ Township Bazaar (Active)',
      );
      const pending =
          'Pending requests: 2.\n'
          '• 2026-09-26 · Transfer · Dell Latitude 5420 · 2 units to Township '
          'Bazaar · by Usman User · Pending\n'
          '• 2026-09-26 · Assignment · HP ProBook 450 · assign to Usman User · '
          'by Ali Admin · Pending';
      expect(direct('pending requests'), pending);
      // "Open requests" is the same question in the words people usually use.
      expect(direct('list the open requests'), pending);
      expect(direct('how many open requests are there?'), pending);
      // "Open" on its own says nothing about a status, so it is not a request
      // question at all and the model gets it.
      expect(direct('open the dashboard'), isNull);
    });

    test('users, a department and one person', () {
      expect(
        direct('how many users'),
        startsWith(
          'User accounts: 6 in all - 1 Super Admin, 2 Admin, 3 User. 5 active.',
        ),
      );
      expect(
        direct('IT department'),
        'The IT department has 3 user accounts:\n'
        '• Ali Admin (Admin, IT)\n'
        '• Ayesha Khan (User, IT)\n'
        '• Usman User (User, IT)',
      );
      expect(
        direct('what does Ayesha Khan have?'),
        'Ayesha Khan (User, IT) holds 1 unit, in 1 asset record:\n'
        '• ABC-123 (Dell Latitude 5420): 1 unit',
      );
    });

    test('a follow-up is answered from what the question before it named', () {
      expect(
        direct('and at head office?', previous: 'How many laptops do we have?'),
        startsWith('At Head Office, in the Laptop category: 10 units'),
      );
      expect(
        direct('and its warranty?', previous: 'ABC-123'),
        'ABC-123 (Dell Latitude 5420)\n'
        'Warranty: ends on 2027-01-10, in 103 days.',
      );
    });

    test('the answer stays on the device: it is never part of the wire', () {
      final context = fx.ask('How many laptops do we have?').context;
      expect(context.directAnswer, isNotNull);
      expect(context.toJson().containsKey('directAnswer'), isFalse);
      expect(fx.wire(context), isNot(contains('16 units in 2 asset records')));
    });

    test('an answer names people only by display name', () {
      for (final question in [
        'assigned assets',
        'who has ABC-123',
        'how many users',
        'pending requests',
        'what does Ayesha Khan have?',
        'ABC-123',
      ]) {
        final answer = direct(question)!;
        expect(answer, isNot(contains('@')), reason: question);
        for (final uid in fx.allUids) {
          expect(answer, isNot(contains(uid)), reason: question);
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // LEFT TO THE MODEL
  // ---------------------------------------------------------------------------

  group('Everything else goes to the model', () {
    const questions = [
      // A reason, a judgement, a comparison, something written.
      'why are so many laptops damaged?',
      'compare laptops and monitors',
      'which laptops should we replace?',
      'write an email about damaged stock',
      'explain the inventory',
      'What can you do?',
      // A negation turns the list inside out.
      'which laptops are not at head office',
      'laptops except the damaged ones',
      // Instructions, English and Roman Urdu.
      'transfer 5 laptops to Township Bazaar',
      'please assign ABC-123 to Ayesha Khan',
      'ABC-123 Ayesha ko assign kar do',
      'Township Bazaar ko 5 laptops bhejo',
      // A number that is not a time window.
      'how many laptops were bought in 2024',
      'transfers in the last 3 months',
      // A word the rules do not know.
      'laptops by brand',
      'kya aap laptops ke baare mein bata sakte hain',
      'ہیڈ آفس میں کتنے لیپ ٹاپ ہیں',
      'IT-LAP-999 details',
      // Two things at once the lists cannot combine.
      'damaged laptops at Township',
      'total value of damaged assets',
      // Conversation, and nothing asked.
      'hello',
      'Assalam o Alaikum',
      'ok',
      'stock?',
    ];

    for (final question in questions) {
      test('"$question"', () => expect(direct(question), isNull));
    }
  });

  // ---------------------------------------------------------------------------
  // ONLY WHAT THE ACCOUNT MAY SEE, ONLY WHEN IT WAS ALL READ
  // ---------------------------------------------------------------------------

  group('Permissions', () {
    test('a User is not told who holds an asset', () {
      expect(
        direct('who has ABC-123', role: 'user'),
        'ABC-123 (Dell Latitude 5420): 1 unit assigned.',
      );
      expect(
        direct('assigned assets', role: 'user'),
        isNot(contains('Ayesha')),
      );
      expect(
        direct('where is ABC-123?', role: 'user'),
        isNot(contains('Ayesha')),
      );
    });

    test('a User\'s questions about people go to the model, with the note', () {
      final result = fx.ask('how many users', role: 'user');
      expect(result.context.directAnswer, isNull);
      expect(result.context.notes.join(), contains('user directory'));
    });

    test('a User sees only their own requests', () {
      expect(
        direct('pending requests', role: 'user'),
        'Your pending requests: 1.\n'
        '• 2026-09-26 · Transfer · Dell Latitude 5420 · 2 units to Township '
        'Bazaar · by Usman User · Pending',
      );
    });

    test('an account not linked to an Admin is still answered', () {
      // Being linked to an Admin decides who owns what this account adds,
      // not what it may read: a User reads all inventory, read-only.
      final unlinked = fx.person(fx.usmanUid, 'Usman User', 'user');
      final result = fx.ask(
        'How many laptops do we have?',
        role: 'user',
        profile: unlinked,
      );
      expect(
        result.context.directAnswer,
        startsWith('Laptop category: 16 units in 2 asset records'),
      );
    });
  });

  group('Data that was not read in full', () {
    const loading = LocalAiSourceState(loading: true);
    const failed = LocalAiSourceState(error: 'permission-denied');

    test('inventory still loading or failed', () {
      expect(
        direct('How many laptops do we have?', inventoryState: loading),
        isNull,
      );
      expect(direct('total inventory', inventoryState: failed), isNull);
      expect(
        direct(
          'total inventory',
          snapshot: fx.snapshotOf(fx.inventory, loading: true),
        ),
        isNull,
      );
      expect(direct('total inventory', inScope: false), isNull);
    });

    test('transfer records still loading or failed', () {
      expect(direct('bazaar stock', movementState: loading), isNull);
      expect(
        direct('Township Bazaar mein kitna stock hai', movementState: failed),
        isNull,
      );
      expect(direct('where is ABC-123?', movementState: loading), isNull);
      expect(direct('transfers this week', movementState: loading), isNull);
    });

    test('requests or the user directory still loading', () {
      expect(direct('pending requests', requestState: loading), isNull);
      expect(direct('how many users', peopleState: loading), isNull);
    });

    test('a figure that needs no transfer records is still answered', () {
      expect(
        direct('available stock', movementState: loading),
        startsWith('Available at Head Office: 22 units'),
      );
    });
  });
}
