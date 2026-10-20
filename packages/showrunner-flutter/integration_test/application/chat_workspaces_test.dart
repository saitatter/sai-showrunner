import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/chat_workspace.dart';
import 'package:showrunner_flutter/features/chat/commands_workspace.dart';
import 'package:showrunner_flutter/graph/domain/automation_factories.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'manages commands and shared chat through the Windows application',
    (tester) async {
      final root = await createShowRunnerFixtureDirectory();
      tester.view.physicalSize = const ui.Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => root.delete(recursive: true));
      await AutomationRepository(
        File('${root.path}/automations/chat-command.yaml'),
      ).save(createEventAutomation(plugin: 'ShowRunner', trigger: 'autoRun'));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('chat-capture'),
          child: buildShowRunnerTestApp(
            dataService: ShowRunnerDataService(root),
          ),
        ),
      );
      await _wait(tester, () => tester.any(find.text('Chat Commands')));
      await tester.ensureVisible(find.text('Chat Commands').first);
      await tester.tap(find.text('Chat Commands').first);
      await _wait(
        tester,
        () =>
            tester.any(find.byType(CommandsWorkspace)) &&
            tester
                .widget<CommandsWorkspace>(find.byType(CommandsWorkspace))
                .manager
                .loaded,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'New command'));
      await _wait(tester, () => tester.any(find.byType(AlertDialog)));
      await tester.enterText(_field('Name'), 'Hello command');
      await tester.ensureVisible(_field('Aliases (comma separated)'));
      await tester.enterText(_field('Aliases (comma separated)'), '!hi');
      await tester.tap(find.widgetWithText(FilledButton, 'Save command'));
      final manager = tester
          .widget<CommandsWorkspace>(find.byType(CommandsWorkspace))
          .manager;
      await _wait(
        tester,
        () =>
            manager.commands.length == 1 &&
            tester.any(find.text('Hello command')) &&
            !tester.any(find.byType(AlertDialog)),
      );
      expect(manager.commands.single.aliases, ['!hi']);
      await _capture(tester, 'chat-commands.png');
      await tester.tap(find.byTooltip('Edit command'));
      await _wait(tester, () => tester.any(_field('Name').hitTestable()));
      await tester.enterText(_field('Name'), 'Edited command');
      await tester.tap(find.widgetWithText(FilledButton, 'Save command'));
      await _wait(
        tester,
        () =>
            manager.commands.single.name == 'Edited command' &&
            !tester.any(find.byType(AlertDialog)),
      );
      await tester.ensureVisible(find.text('Chat').first);
      await tester.tap(find.text('Chat').first);
      await _wait(tester, () => tester.any(find.byType(ChatWorkspace)));
      final chat = tester
          .widget<ChatWorkspace>(find.byType(ChatWorkspace))
          .runtime;
      chat.ingest(
        ChatMessage(
          platform: ChatPlatform.twitch,
          id: 'twitch-command',
          channelId: 'channel',
          userId: 'viewer',
          userName: 'Ada',
          text: '!hi Ada',
          receivedAt: DateTime.utc(2026),
        ),
      );
      chat.ingest(
        ChatMessage(
          platform: ChatPlatform.youtube,
          id: 'youtube-message',
          channelId: 'live',
          userId: 'yt-viewer',
          userName: 'YouTube Viewer',
          text: 'Hello from YouTube',
          receivedAt: DateTime.utc(2026),
        ),
      );
      await _wait(
        tester,
        () =>
            manager.countersFor(manager.commands.single.id).dispatched == 1 &&
            tester.any(find.text('Hello from YouTube')),
      );
      await _capture(tester, 'unified-chat.png');
      await tester.tap(find.widgetWithText(ChoiceChip, 'youtube'));
      await tester.pump();
      expect(find.text('Hello from YouTube'), findsOneWidget);
      expect(find.text('!hi Ada'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All platforms'));
      await tester.pump();
      expect(find.text('!hi Ada'), findsOneWidget);
      await tester.tap(find.byTooltip('Message and user actions').last);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Reply').last);
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('Message')).controller!.text,
        startsWith('@'),
      );
      await tester.enterText(_field('Message'), '!h');
      await tester.pump();
      expect(find.text('!hi - Edited command'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('Message')).controller!.text,
        '!hi ',
      );
      await tester.enterText(_field('Message'), ':smi');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('Message')).controller!.text,
        '\u{1f600} ',
      );
      await tester.tap(find.byTooltip('Chat preferences'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show timestamps'));
      await tester.tap(find.text('Highlights'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Highlight text or mentions'), 'hello');
      await tester.tap(find.widgetWithText(FilledButton, 'Save preferences'));
      await _wait(tester, () => !tester.any(find.byType(AlertDialog)));
      expect(chat.preferences.timestamps, isTrue);
      expect(chat.preferences.highlightTerms, ['hello']);
      await _capture(tester, 'chat-preferences.png');
      await tester.tap(find.widgetWithText(TextButton, 'Chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'New chat action'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Action label'), 'Global probe');
      await tester.tap(find.text('message').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('global').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save chat action'));
      await _wait(tester, () => chat.configuredActions.length == 1);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Global probe'));
      await tester.pumpAndSettle();
      chat.eventHub.emit('follow', {
        'id': 'native-follow',
        'user_id': 'follower',
        'user_name': 'Fixture follower',
      });
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Events'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('twitch - follow - Fixture follower'),
        findsOneWidget,
      );
      await _capture(tester, 'chat-events.png');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Messages'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Pause view'));
      chat.ingest(
        ChatMessage(
          platform: ChatPlatform.twitch,
          id: 'paused',
          channelId: 'channel',
          userId: 'later',
          userName: 'Later',
          text: 'Arrived while paused',
          receivedAt: DateTime.now(),
        ),
      );
      await tester.pump();
      expect(find.text('Arrived while paused'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Resume view'));
      await tester.pump();
      expect(find.text('Arrived while paused'), findsOneWidget);
      await tester.enterText(_field('Message'), '');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('Message')).focusNode!.hasFocus,
        isFalse,
      );

      await tester.tap(find.text('Chat Commands').first);
      await _wait(tester, () => tester.any(find.byType(CommandsWorkspace)));
      await tester.tap(find.byType(Switch).first);
      await _wait(tester, () => !manager.commands.single.enabled);
      await tester.tap(find.widgetWithText(TextButton, 'Reset counters'));
      await _wait(
        tester,
        () => manager.countersFor(manager.commands.single.id).accepted == 0,
      );
      await tester.tap(find.byTooltip('Delete command'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _wait(tester, () => manager.commands.isEmpty);
      expect(
        await File('${root.path}/automations/chat-command.yaml').exists(),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Future<void> _wait(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Chat workspace did not become ready.');
    }
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('chat-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = await Directory('.tmp/chat-ui').create(recursive: true);
    await File(
      '${output.path}/$name',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
