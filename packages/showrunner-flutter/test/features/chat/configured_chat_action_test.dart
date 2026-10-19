import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/configured_chat_action.dart';

void main() {
  test(
    'chat action definitions round trip immutably and validate executable targets',
    () {
      final platforms = {ChatPlatform.youtube};
      final arguments = {'mode': 'probe'};
      final action = ConfiguredChatAction(
        id: 'probe',
        label: 'Probe',
        automationFile: 'probe.yaml',
        platforms: platforms,
        arguments: arguments,
        scope: ChatActionScope.event,
        icon: 'star',
        color: 'blue',
      );
      platforms.clear();
      arguments.clear();
      expect(action.platforms, {ChatPlatform.youtube});
      expect(action.arguments, {'mode': 'probe'});
      expect(
        ConfiguredChatAction.fromJson(action.toJson()).toJson(),
        action.toJson(),
      );
      expect(
        () => ConfiguredChatAction(
          id: 'bad id',
          label: 'Probe',
          automationFile: 'probe.yaml',
        ),
        throwsFormatException,
      );
      expect(
        () => ConfiguredChatAction(
          id: 'probe',
          label: 'Probe',
          automationFile: '../outside.yaml',
        ),
        throwsFormatException,
      );
      expect(
        () => ConfiguredChatAction(
          id: 'probe',
          label: 'Probe',
          automationFile: 'probe.yaml',
          platforms: {},
        ),
        throwsFormatException,
      );
      expect(
        () => ConfiguredChatAction(
          id: 'probe',
          label: 'Probe',
          automationFile: 'probe.yaml',
          icon: 'unknown',
        ),
        throwsFormatException,
      );
    },
  );
}
