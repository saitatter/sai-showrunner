import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/chat_moderation_dialog.dart';
import 'package:showrunner_flutter/features/chat/unified_chat_runtime.dart';

void main() {
  testWidgets(
    'warning requires a reason and returns it only after confirmation',
    (tester) async {
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  submitted = await showDialog<String>(
                    context: context,
                    builder: (_) => ChatModerationDialog(
                      action: ChatQuickAction.warnUser,
                      message: ChatMessage(
                        platform: ChatPlatform.twitch,
                        id: 'message',
                        channelId: 'channel',
                        userId: 'viewer',
                        userName: 'Viewer',
                        text: 'text',
                        receivedAt: DateTime.utc(2026),
                      ),
                    ),
                  );
                },
                child: const Text('Warn'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Warn'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Respect the rules');
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(submitted, 'Respect the rules');
    },
  );
}
