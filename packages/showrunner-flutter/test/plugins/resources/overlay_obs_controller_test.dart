import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/overlay_source_service.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_obs_controller.dart';
import '../../support/overlay_obs_fixtures.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

OverlayObsController controller(
  RecordingOverlayObsActions actions, {
  Future<int> Function()? port,
}) => OverlayObsController(
  overlayId: 'old',
  width: 1920,
  height: 1080,
  port: port ?? () async => 8282,
  service: actions,
);

void main() {
  test(
    'inspection started before a write cannot publish stale source state',
    () async {
      final actions = RecordingOverlayObsActions()
        ..writeGate = Completer<void>();
      final oldInspection = Completer<OverlayBrowserSourceStatus>();
      actions.inspectRequest = (_) => oldInspection.future;
      final owner = controller(actions);
      await _settle();
      final writing = owner.create(
        'Browser',
        expectedContext: owner.contextToken,
      );
      await _settle();
      oldInspection.complete(
        const OverlayBrowserSourceStatus(connected: false),
      );
      await _settle();
      expect(owner.view.sourceLoading, true);
      expect(owner.view.status, isNull);
      actions.inspectRequest = (_) async => const OverlayBrowserSourceStatus(
        connected: true,
        sourceName: 'Current source',
        isCurrent: true,
      );
      actions.writeGate!.complete();
      expect(await writing, true);
      expect(owner.view.status!.sourceName, 'Current source');
      await owner.close();
    },
  );
  test(
    'loads immutable choices and inspects only on explicit context changes',
    () async {
      final actions = RecordingOverlayObsActions();
      final owner = controller(actions);
      await _settle();
      expect(owner.view.selectedId, 'a');
      expect(owner.view.status!.isCurrent, true);
      expect(() => owner.view.connections.clear(), throwsUnsupportedError);
      owner.setDimensions(3840, 2160);
      await owner.refresh();
      expect(actions.inspected.last, (
        connection: 'a',
        overlay: 'old',
        width: 3840,
        height: 2160,
        port: 8282,
      ));
      await owner.close();
      expect(actions.closes, 0);
    },
  );

  test('A to B to A selection cannot accept the first A reply', () async {
    final actions = RecordingOverlayObsActions();
    final replies = <Completer<OverlayBrowserSourceStatus>>[];
    actions.inspectRequest = (_) {
      final reply = Completer<OverlayBrowserSourceStatus>();
      replies.add(reply);
      return reply.future;
    };
    final owner = controller(actions);
    await _settle();
    owner.select('b');
    await _settle();
    owner.select('a');
    await _settle();
    expect(replies.length, 3);
    replies[2].complete(
      const OverlayBrowserSourceStatus(
        connected: true,
        sourceName: 'Current A',
        isCurrent: true,
      ),
    );
    await _settle();
    replies[0].complete(
      const OverlayBrowserSourceStatus(connected: true, sourceName: 'Old A'),
    );
    replies[1].completeError(StateError('private-obs-marker'));
    await _settle();
    expect(owner.view.status!.sourceName, 'Current A');
    expect(owner.view.error, isNull);
    await owner.close();
  });

  test('replaced service list failure cannot clear current choices', () async {
    final previous = RecordingOverlayObsActions(label: 'Previous');
    final list = Completer<List<ObsConnectionChoice>>();
    previous.list = () => list.future;
    final current = RecordingOverlayObsActions(label: 'Current');
    final owner = controller(previous);
    await _settle();
    owner.configure(
      overlayId: 'new',
      width: 1000,
      height: 600,
      port: () async => 8181,
      service: current,
    );
    await _settle();
    list.completeError(StateError('private-obs-marker'));
    await _settle();
    expect(owner.view.connections.first.name, 'Current a');
    expect(owner.view.error, isNull);
    expect(previous.defaultReads, 0);
    await owner.close();
  });

  test('dialog context from an old document cannot create a source', () async {
    final actions = RecordingOverlayObsActions();
    final owner = controller(actions);
    await _settle();
    final oldDialog = owner.contextToken;
    owner.configure(
      overlayId: 'new',
      width: 1000,
      height: 600,
      port: () async => 8181,
      service: actions,
    );
    expect(
      await owner.create('Old dialog result', expectedContext: oldDialog),
      false,
    );
    expect(actions.created, isEmpty);
    await owner.close();
  });

  test('target changes during port lookup prevent physical writes', () async {
    final actions = RecordingOverlayObsActions();
    final port = Completer<int>();
    final owner = controller(actions, port: () => port.future);
    await _settle();
    final writing = owner.create(
      'Browser',
      expectedContext: owner.contextToken,
    );
    await _settle();
    owner.configure(
      overlayId: 'new',
      width: 1000,
      height: 600,
      port: () async => 8181,
      service: actions,
    );
    port.complete(8282);
    expect(await writing, false);
    expect(actions.created, isEmpty);
    expect(actions.inspected, isEmpty);
    await owner.close();
  });

  test(
    'duplicate creation shares accepted immutable target ownership',
    () async {
      final actions = RecordingOverlayObsActions()
        ..writeGate = Completer<void>();
      final owner = controller(actions);
      await _settle();
      final token = owner.contextToken;
      final writing = owner.create('Browser', expectedContext: token);
      expect(owner.create('Duplicate', expectedContext: token), same(writing));
      await _settle();
      owner.setDimensions(3840, 2160);
      actions.writeGate!.complete();
      expect(await writing, true);
      expect(actions.created.single, (
        connection: 'a',
        overlay: 'old',
        width: 1920,
        height: 1080,
        port: 8282,
      ));
      expect(owner.view.status, isNull);
      await owner.close();
    },
  );

  test(
    'fix and launch use the selected borrowed service without closing it',
    () async {
      final actions = RecordingOverlayObsActions();
      final owner = controller(actions);
      await _settle();
      owner.select('b');
      await owner.refresh();
      expect(await owner.fix(expectedContext: owner.contextToken), true);
      expect(actions.fixed.single.connection, 'b');
      expect(await owner.open(), true);
      expect(actions.opened, ['b']);
      await owner.close();
      expect(actions.closes, 0);
    },
  );

  test(
    'provider failures leave safe retryable state without exception payloads',
    () async {
      final actions = RecordingOverlayObsActions();
      final owner = controller(actions);
      await _settle();
      actions.inspectRequest = (_) async =>
          throw StateError('private-obs-marker');
      await owner.refresh();
      expect(owner.view.error, isNot(contains('private-obs-marker')));
      expect(owner.view.sourceLoading, false);
      actions.failWrite = true;
      expect(
        await owner.create('Browser', expectedContext: owner.contextToken),
        false,
      );
      expect(owner.view.error, isNot(contains('private-obs-marker')));
      actions.failOpen = true;
      expect(await owner.open(), isNull);
      expect(owner.view.error, isNot(contains('private-obs-marker')));
      await owner.close();
    },
  );

  test(
    'close drains an accepted provider write and ignores delayed notifications',
    () async {
      final actions = RecordingOverlayObsActions()
        ..writeGate = Completer<void>();
      final owner = controller(actions);
      await _settle();
      final writing = owner.create(
        'Browser',
        expectedContext: owner.contextToken,
      );
      await _settle();
      var notifications = 0;
      owner.addListener(() => notifications++);
      var closed = false;
      final closing = owner.close().then((_) => closed = true);
      await _settle();
      expect(closed, false);
      actions.writeGate!.complete();
      await writing;
      await closing;
      expect(notifications, 0);
      expect(actions.closes, 0);
    },
  );
}
