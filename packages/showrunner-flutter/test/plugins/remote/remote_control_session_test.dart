import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/remote/remote_control_session.dart';
import 'package:showrunner_flutter/plugins/remote/remote_protocol.generated.dart';
import 'package:showrunner_flutter/plugins/remote/satellite/protocol.dart';
import 'package:showrunner_flutter/plugins/remote/satellite/transport.dart';

final class _Channel implements SatelliteDataChannel {
  @override
  String get label => 'controlChannel';
  @override
  SatelliteChannelState state = SatelliteChannelState.open;
  final sent = <String>[];
  Completer<void>? sendGate;
  void Function(String)? _message;
  void Function(SatelliteChannelState)? _state;
  @override
  set onMessage(void Function(String)? value) {
    _message = value;
  }

  @override
  set onStateChanged(void Function(SatelliteChannelState)? value) {
    _state = value;
  }

  @override
  Future<void> sendText(String message) async {
    sent.add(message);
    await sendGate?.future;
  }

  @override
  Future<void> close() async {
    state = SatelliteChannelState.closed;
    if (sendGate?.isCompleted == false) sendGate!.complete();
    _state?.call(state);
  }

  void emit(Map<String, dynamic> message) =>
      _message?.call(jsonEncode(encodeRemoteWire(message, 'fixture')));
}

void main() {
  testWidgets(
    'starts the request deadline before a blocked native send and closes stale channels',
    (tester) async {
      final channel = _Channel()..sendGate = Completer<void>();
      var invalid = 0;
      final session = RemoteControlSession(
        channel: channel,
        resourceId: 'fixture',
        requestPrefix: 'probe',
        requestTimeout: const Duration(milliseconds: 100),
        onRequest: (_, _) async => null,
        onInvalid: () async {
          invalid++;
          await channel.close();
        },
      );
      final request = session.call('read', []);
      final checked = expectLater(request, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(milliseconds: 100));
      await checked;
      await session.close();
      expect(invalid, 1);
      expect(channel.state, SatelliteChannelState.closed);
      expect(channel.sent, hasLength(1));
      channel.emit({'responseId': 'probe-0', 'result': 'late'});
      await expectLater(session.call('late', []), throwsStateError);
    },
  );

  testWidgets('bounds pending calls and cancels all owned timers on close', (
    tester,
  ) async {
    final channel = _Channel();
    final session = RemoteControlSession(
      channel: channel,
      resourceId: 'fixture',
      requestPrefix: 'probe',
      onRequest: (_, _) async => null,
      onInvalid: channel.close,
    );
    final calls = [
      for (var index = 0; index < 64; index++) session.call('read', []),
    ];
    await expectLater(session.call('overflow', []), throwsStateError);
    final checked = [
      for (final call in calls) expectLater(call, throwsStateError),
    ];
    await session.close();
    await Future.wait(checked);
    expect(channel.sent, hasLength(64));
  });

  testWidgets(
    'expired inbound work retains admission slots and late results never send',
    (tester) async {
      final channel = _Channel();
      final work = Completer<Object?>();
      var calls = 0;
      final session = RemoteControlSession(
        channel: channel,
        resourceId: 'fixture',
        requestPrefix: 'probe',
        requestTimeout: const Duration(milliseconds: 100),
        onRequest: (_, _) {
          calls++;
          return work.future;
        },
        onInvalid: channel.close,
      );
      for (var index = 0; index < 16; index++) {
        channel.emit({
          'requestId': 'inbound-$index',
          'name': 'read',
          'args': [],
        });
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 16);
      expect(channel.sent, hasLength(16));
      channel.emit({'requestId': 'overflow', 'name': 'read', 'args': []});
      await tester.pump();
      expect(channel.state, SatelliteChannelState.closed);
      expect(calls, 16);
      work.complete('private-late-marker');
      await tester.pump();
      await session.close();
      expect(channel.sent, hasLength(16));
      expect(channel.sent.join(), isNot(contains('private-late-marker')));
    },
  );
}
