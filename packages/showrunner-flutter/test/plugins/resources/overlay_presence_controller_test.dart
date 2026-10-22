import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_presence.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_presence_controller.dart';

class _Reader implements OverlayPresenceReader {
  _Reader(this.read);
  final Future<OverlayPresence> Function(String) read;
  int calls = 0;
  @override
  Future<OverlayPresence> getPresence(String id) {
    calls++;
    return read(id);
  }

  @override
  String browserSourceUrl(String id) => 'http://localhost:8282/overlays/$id';
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);
OverlayPresence _connected(String id) =>
    OverlayPresence(overlayId: id, connected: true, subscribers: 2);

void main() {
  test('a delayed reader cannot replace the new resource observer', () async {
    final old = Completer<OverlayPresenceReader?>();
    final previous = _Reader((id) async => _connected(id));
    final current = _Reader((id) async => _connected(id));
    final controller = OverlayPresenceController('old', old.future);
    controller.configure('new', Future.value(current));
    await _settle();
    old.complete(previous);
    await _settle();
    expect(controller.value.presence, _connected('new'));
    expect(controller.value.url, endsWith('/new'));
    expect(previous.calls, 0);
    await controller.close();
  });

  test('a delayed presence reply cannot overwrite the next resource', () async {
    final reply = Completer<OverlayPresence>();
    final previous = _Reader((_) => reply.future);
    final current = _Reader((id) async => _connected(id));
    final controller = OverlayPresenceController('old', Future.value(previous));
    await _settle();
    controller.configure('new', Future.value(current));
    await _settle();
    reply.complete(_connected('old'));
    await _settle();
    expect(controller.value.presence, _connected('new'));
    await controller.close();
  });

  test('overlapping polls share one accepted read', () async {
    final reply = Completer<OverlayPresence>();
    final reader = _Reader((_) => reply.future);
    final controller = OverlayPresenceController('one', Future.value(reader));
    await _settle();
    final first = controller.refresh(), second = controller.refresh();
    expect(first, same(second));
    expect(reader.calls, 1);
    reply.complete(_connected('one'));
    await first;
    expect(controller.value.presence, _connected('one'));
    await controller.close();
  });

  test(
    'synchronous read failures stay disconnected and permit retry',
    () async {
      final reader = _Reader((_) => throw StateError('private-token'));
      final controller = OverlayPresenceController('one', Future.value(reader));
      await _settle();
      await controller.refresh();
      expect(reader.calls, 2);
      expect(controller.value.presence.connected, false);
      expect(controller.value.url, 'http://localhost:8282/overlays/one');
      await controller.close();
    },
  );

  test(
    'close drains accepted replies without publishing after disposal',
    () async {
      final reply = Completer<OverlayPresence>();
      final controller = OverlayPresenceController(
        'one',
        Future.value(_Reader((_) => reply.future)),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      await _settle();
      final before = notifications;
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      await _settle();
      expect(closed, false);
      reply.complete(_connected('one'));
      await closing;
      expect(notifications, before);
      await controller.refresh();
      controller.dispose();
    },
  );

  test(
    'foreign identity replies do not change the observed resource',
    () async {
      final reader = _Reader((_) async => _connected('foreign'));
      final controller = OverlayPresenceController('one', Future.value(reader));
      await _settle();
      expect(controller.value.presence, OverlayPresence.disconnected('one'));
      expect(await controller.port, 8282);
      await controller.close();
    },
  );

  test(
    'already failed startup futures are observed without leaking their payload',
    () async {
      final controller = OverlayPresenceController(
        'one',
        Future.error(StateError('private-token')),
      );
      await _settle();
      expect(controller.value.presence.connected, false);
      expect(await controller.port, 8181);
      await controller.close();
    },
  );
}
