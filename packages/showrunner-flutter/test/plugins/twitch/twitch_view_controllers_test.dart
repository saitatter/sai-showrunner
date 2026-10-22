import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/twitch/ui/twitch_chat_activity.dart';
import 'package:showrunner_flutter/plugins/twitch/ui/twitch_channel_view_controller.dart';
import 'package:showrunner_flutter/plugins/twitch/channel_runtime.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  test(
    'chat history is bounded and replacement streams cannot publish old messages',
    () async {
      final first = StreamController<RuntimeMap>.broadcast(),
          second = StreamController<RuntimeMap>.broadcast();
      final controller = TwitchChatActivityController(first.stream);
      for (var i = 0; i < 30; i++) {
        first.add({'chatter_user_name': 'Test', 'message': 'message $i'});
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.history.length, 20);
      expect(controller.value.history.first, 'Test: message 29');
      expect(() => controller.value.history.clear(), throwsUnsupportedError);
      controller.configure(second.stream);
      first.add({'message': 'stale'});
      second.add({'message': 'current'});
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.message, 'current');
      await controller.close();
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isFalse);
      await first.close();
      await second.close();
    },
  );
  test(
    'channel refresh shares accepted work, fails safely and drains on close',
    () async {
      final response = Completer<TwitchChannelSnapshot>();
      var calls = 0;
      final controller = TwitchChannelViewController(
        load: () {
          calls++;
          return response.future;
        },
      );
      final read = controller.refresh();
      expect(identical(read, controller.refresh()), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(controller.value.loading, isTrue);
      response.completeError(StateError('private-marker'));
      await read;
      expect(controller.value.failed, isTrue);
      expect(controller.value.loading, isFalse);
      await controller.close();
      await controller.refresh();
      expect(calls, 1);
    },
  );
  test('late channel reads cannot publish after close', () async {
    final response = Completer<TwitchChannelSnapshot>();
    final controller = TwitchChannelViewController(load: () => response.future);
    final read = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    var notifications = 0;
    controller.addListener(() => notifications++);
    var closed = false;
    final closing = controller.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    response.completeError(StateError('late'));
    await Future.wait([read, closing]);
    expect(notifications, 0);
  });
}
