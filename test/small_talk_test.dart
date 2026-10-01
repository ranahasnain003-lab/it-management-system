/// Greetings and other small talk: recognised as conversation by both
/// assistants, without weakening how inventory questions are answered.
///
/// The fixtures (an organisation with two Admins' inventory, real providers
/// over an in-memory Firestore) are the Local AI context tests' own.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/action_planner.dart';
import 'package:it_management_system/core/ai/assistant_actions.dart';
import 'package:it_management_system/core/ai/inventory_assistant.dart';
import 'package:it_management_system/core/ai/local/local_ai_inventory_context.dart';
import 'package:it_management_system/core/ai/local/local_ai_models.dart';
import 'package:it_management_system/core/ai/local/widgets/local_ai_message_bubble.dart';
import 'package:it_management_system/core/ai/small_talk.dart';

import 'local_ai_context_test.dart' as fx;

void main() {
  group('SmallTalk.read', () {
    const smallTalk = <String, SmallTalkKind>{
      'Hello': SmallTalkKind.greeting,
      'hello!!': SmallTalkKind.greeting,
      'Hi': SmallTalkKind.greeting,
      'hii 👋': SmallTalkKind.greeting,
      'hlo': SmallTalkKind.greeting,
      'Hey there': SmallTalkKind.greeting,
      'Hi team': SmallTalkKind.greeting,
      'Good morning': SmallTalkKind.greeting,
      'gud morning': SmallTalkKind.greeting,
      'Good evening sir': SmallTalkKind.greeting,
      'ہیلو': SmallTalkKind.greeting,
      'Assalam o Alaikum': SmallTalkKind.salam,
      'Assalam-o-Alaikum!': SmallTalkKind.salam,
      'assalamualaikum': SmallTalkKind.salam,
      'Assalamu alaikum': SmallTalkKind.salam,
      'Asalam o alaikum': SmallTalkKind.salam,
      'Aslam o alaikum': SmallTalkKind.salam,
      'Asslam o alaikum': SmallTalkKind.salam,
      'Aslamualaikum': SmallTalkKind.salam,
      'As salamu alaykum': SmallTalkKind.salam,
      'Assalam o Alaikum wa rahmatullah': SmallTalkKind.salam,
      'Assalam o alaikum wa rehmatullah wa barakatuhu': SmallTalkKind.salam,
      'Salam': SmallTalkKind.salam,
      'Salam bhai': SmallTalkKind.salam,
      'AOA': SmallTalkKind.salam,
      'AOA sir': SmallTalkKind.salam,
      'Walaikum assalam': SmallTalkKind.salam,
      'wa alaikum': SmallTalkKind.salam,
      'السلام علیکم': SmallTalkKind.salam,
      'السلام و علیکم': SmallTalkKind.salam,
      'How are you?': SmallTalkKind.howAreYou,
      'How are you today?': SmallTalkKind.howAreYou,
      'how are u doing': SmallTalkKind.howAreYou,
      "how's it going": SmallTalkKind.howAreYou,
      'how r u': SmallTalkKind.howAreYou,
      'kaise ho': SmallTalkKind.howAreYou,
      'kesy ho': SmallTalkKind.howAreYou,
      'Aap kaise hain?': SmallTalkKind.howAreYou,
      'ap kaise hain': SmallTalkKind.howAreYou,
      'kya haal hai': SmallTalkKind.howAreYou,
      'kia hal hai': SmallTalkKind.howAreYou,
      'آپ کیسے ہیں؟': SmallTalkKind.howAreYou,
      'Thanks!': SmallTalkKind.thanks,
      'Thank you so much': SmallTalkKind.thanks,
      'thanks alot': SmallTalkKind.thanks,
      'thnx': SmallTalkKind.thanks,
      'ok thanks': SmallTalkKind.thanks,
      'shukriya': SmallTalkKind.thanks,
      'shukriya bhai': SmallTalkKind.thanks,
      'بہت شکریہ': SmallTalkKind.thanks,
      'Khuda Hafiz': SmallTalkKind.farewell,
      'Allah Hafiz': SmallTalkKind.farewell,
      'اللّٰہ حافظ': SmallTalkKind.farewell,
      'see ya': SmallTalkKind.farewell,
      'bye': SmallTalkKind.farewell,
    };

    for (final entry in smallTalk.entries) {
      test('"${entry.key}" is small talk', () {
        final read = SmallTalk.read(entry.key);
        expect(read, isNotNull);
        expect(read!.kinds, contains(entry.value));
      });
    }

    test('several kinds in one message are all recognised', () {
      final read = SmallTalk.read('Hi, how are you?')!;
      expect(
        read.kinds,
        containsAll([SmallTalkKind.greeting, SmallTalkKind.howAreYou]),
      );
    });

    // Anything more than small talk is a question and must be answered as
    // one - a false "yes" here would swallow it. Names that look like a
    // greeting word are people to ask about, not greetings.
    const questions = [
      '',
      '   ',
      'Hello, how many laptops are at Head Office?',
      'Hi, where is ABC-123?',
      'Assalam o Alaikum, show me damaged assets',
      'Thanks, now show the pending requests',
      'How are the assets at Head Office?',
      'How are you today with the stock?',
      'What is our total inventory?',
      'hi-speed router stock',
      'morning shift assets',
      'today',
      'good',
      'ok',
      'Alam',
      'and Alam?',
      'Alam sahib',
      'Aslam',
      'and Aslam?',
      'Show Aslam requests',
      'Rahmatullah',
      'and Rahmatullah?',
      'Barakat',
      'Salam Khan ki requests',
      'blah blah zzz',
      'hello 5',
    ];

    for (final question in questions) {
      test('"$question" is not small talk', () {
        expect(SmallTalk.read(question), isNull);
      });
    }

    test('replies are short, natural and name no figure', () {
      for (final message in smallTalk.keys) {
        final reply = SmallTalk.read(message)!.reply;
        expect(reply.length, lessThan(120), reason: message);
        expect(RegExp(r'\d').hasMatch(reply), isFalse, reason: message);
      }
      expect(
        SmallTalk.read('Assalam o Alaikum')!.reply,
        startsWith('Wa alaikum assalam!'),
      );
      expect(
        SmallTalk.read('Good morning')!.reply,
        startsWith('Good morning!'),
      );
      expect(SmallTalk.read('How are you?')!.reply, contains("I'm doing well"));
      expect(SmallTalk.read('Khuda Hafiz')!.reply, startsWith('Allah Hafiz!'));
    });

    test(
      'a goodbye or a thank-you is answered as one, even after a greeting',
      () {
        expect(
          SmallTalk.read('salam, khuda hafiz')!.reply,
          startsWith('Allah Hafiz!'),
        );
        expect(
          SmallTalk.read('thanks, khuda hafiz')!.reply,
          startsWith("You're welcome! Allah Hafiz!"),
        );
        expect(
          SmallTalk.read('good evening, bye')!.reply,
          startsWith('Goodbye!'),
        );
        expect(
          SmallTalk.read('hi thanks')!.reply,
          startsWith("You're welcome!"),
        );
        expect(
          SmallTalk.read('salam, thanks')!.reply,
          startsWith("Wa alaikum assalam! You're welcome!"),
        );
      },
    );
  });

  group('in-app assistant (InventoryAssistant)', () {
    final snapshot = fx.snapshotOf(fx.inventory);

    for (final greeting in [
      'Hello',
      'Hi',
      'Assalam o Alaikum',
      'How are you?',
      'Good morning',
    ]) {
      test(
        '"$greeting" gets a short greeting, not the "which figure" message',
        () {
          final reply = InventoryAssistant().answer(greeting, snapshot);

          expect(reply.understood, isTrue);
          expect(reply.text, isNot(contains('did not catch')));
          expect(
            RegExp(r'\d').hasMatch(reply.text),
            isFalse,
            reason: reply.text,
          );
          expect(reply.asset, isNull);
        },
      );

      test('"$greeting" is never turned into an action', () {
        final plan = ActionPlanner(finder: InventoryAssistant()).plan(
          greeting,
          snapshot,
          const AssistantPermissions(role: 'super_admin'),
        );
        expect(plan, isNull);
      });
    }

    test('a greeting in front of a question still gets the figure', () {
      final withGreeting = InventoryAssistant().answer(
        'Hello, how many units are at head office?',
        snapshot,
      );
      final plain = InventoryAssistant().answer(
        'how many units are at head office?',
        snapshot,
      );

      expect(withGreeting.understood, isTrue);
      expect(withGreeting.text, contains('Head Office has'));
      expect(withGreeting.text, plain.text);
      expect(withGreeting.text, isNot(contains('How can I help')));
    });

    test('a follow-up after a greeting stays on the same asset', () {
      final assistant = InventoryAssistant();
      assistant.answer('where is ABC-123', snapshot);
      assistant.answer('Thanks', snapshot);

      final followUp = assistant.answer('and its warranty?', snapshot);

      expect(followUp.asset?.assetId, 'ABC-123');
    });

    test('an unclear question still asks for a rephrase', () {
      expect(
        InventoryAssistant().answer('blah blah zzz', snapshot).text,
        contains('did not catch'),
      );
    });
  });

  group('Local AI context', () {
    test('a greeting sends no records and says why', () {
      final result = fx.ask(
        'Hello',
        previous: 'Where is asset ABC-123?',
        rememberedAssetId: fx.abc123.id,
      );
      final context = result.context;

      expect(context.sections, isEmpty);
      expect(context.notes, [LocalAiInventoryContext.smallTalkNote]);
      expect(result.focusAsset, isNull);
      // The previous question's asset is not carried along with "Hello".
      expect(jsonEncode(context.toJson()), isNot(contains('ABC-123')));
    });

    test('small talk in every form sends no records', () {
      for (final message in [
        'Hi',
        'Assalam o Alaikum',
        'How are you?',
        'Good morning',
        'Thanks',
        'Khuda Hafiz',
      ]) {
        final context = fx
            .ask(message, previous: 'Which requests are pending?')
            .context;
        expect(context.sections, isEmpty, reason: message);
      }
    });

    test(
      'a question with a greeting in front is answered from the data as before',
      () {
        final withGreeting = fx.ask('Hello, where is asset ABC-123?').context;
        final plain = fx.ask('Where is asset ABC-123?').context;

        expect(fx.titles(withGreeting), fx.titles(plain));
        expect(fx.titles(withGreeting), contains(startsWith('Asset ABC-123')));
      },
    );

    test('a refused account is still refused, greeting or not', () {
      final context = fx
          .ask('Hello', askedFor: fx.usmanUid, signedIn: fx.adminAUid)
          .context;

      expect(context.sections, isEmpty);
      expect(
        context.notes,
        isNot(contains(LocalAiInventoryContext.smallTalkNote)),
      );
    });

    test(
      'the service reads no records for a greeting and keeps the follow-up memory',
      () async {
        final world = await fx.World.signedInAs(fx.adminAUid);
        addTearDown(world.dispose);

        final greeting = await world.ask('Hello');
        expect(greeting!.sections, isEmpty);
        expect(greeting.notes, [LocalAiInventoryContext.smallTalkNote]);
        // No inventory listener was even started for it.
        expect(world.assetService.streams, 0);

        await world.ask('Where is asset ABC-123?');
        await world.ask('Thanks', previous: 'Where is asset ABC-123?');
        final followUp = await world.ask('and its status?', previous: 'Thanks');

        expect(fx.titles(followUp!), contains(startsWith('Asset ABC-123')));
      },
    );

    test(
      'the service still refuses an inactive account that says hello',
      () async {
        final world = await fx.World.signedInAs(
          fx.adminAUid,
          profileOverride: {'status': 'inactive'},
        );
        addTearDown(world.dispose);

        final context = await world.ask('Hello');

        expect(context!.sections, isEmpty);
        expect(
          context.notes,
          isNot(contains(LocalAiInventoryContext.smallTalkNote)),
        );
        expect(world.assetService.streams, 0);
      },
    );
  });

  group('answer badge', () {
    Future<void> pumpAnswer(WidgetTester tester, int sections) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalAiMessageBubble(
              message: LocalAiMessage(
                id: 'a1',
                role: 'assistant',
                content: 'Hello! How can I help you today?',
                appContext: LocalAiAppContextUsage(
                  used: true,
                  source: 'PSBA IT Inventory (Firebase)',
                  retrievedAt: null,
                  sections: sections,
                  tokens: 100,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a greeting answer is not labelled as inventory data', (
      tester,
    ) async {
      await pumpAnswer(tester, 0);
      expect(
        find.textContaining('Based on your IT Inventory data'),
        findsNothing,
      );
    });

    testWidgets('an answer built on inventory data still is', (tester) async {
      await pumpAnswer(tester, 2);
      expect(
        find.textContaining('Based on your IT Inventory data'),
        findsOneWidget,
      );
    });
  });
}
