import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/lifecycle/application_runtime.dart';

void main() {
  test(
    'starts dependencies once and awaits reverse owned teardown once',
    () async {
      final events = <String>[];
      final runtime = ApplicationRuntime(
        resources: [
          for (final name in ['hub', 'queue', 'producer'])
            ApplicationRuntimeResource(
              name: name,
              start: () async => events.add('start:$name'),
              stop: () async => events.add('stop:$name'),
            ),
        ],
      );
      await Future.wait([runtime.start(), runtime.start()]);
      await Future.wait([runtime.shutdown(), runtime.shutdown()]);
      expect(events, [
        'start:hub',
        'start:queue',
        'start:producer',
        'stop:producer',
        'stop:queue',
        'stop:hub',
      ]);
      expect(runtime.state, ApplicationRuntimeState.stopped);
      await expectLater(runtime.start(), throwsStateError);
    },
  );
  test(
    'shutdown waits for startup in flight and prevents later producers',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final events = <String>[];
      final runtime = ApplicationRuntime(
        resources: [
          ApplicationRuntimeResource(
            name: 'dependency',
            start: () async {
              entered.complete();
              await release.future;
              events.add('ready');
            },
            stop: () async => events.add('stop:dependency'),
          ),
          ApplicationRuntimeResource(
            name: 'producer',
            start: () async => events.add('start:producer'),
            stop: () async => events.add('stop:producer'),
          ),
        ],
      );
      final start = runtime.start();
      await entered.future;
      final stop = runtime.shutdown();
      expect(events, isEmpty);
      release.complete();
      await Future.wait([start, stop]);
      expect(events, ['ready', 'stop:producer', 'stop:dependency']);
    },
  );
  test(
    'failed startup releases constructed resources and preserves its error',
    () async {
      final events = <String>[];
      final failure = StateError('start failed');
      final runtime = ApplicationRuntime(
        resources: [
          ApplicationRuntimeResource(
            name: 'sink',
            stop: () async => events.add('sink'),
          ),
          ApplicationRuntimeResource(
            name: 'producer',
            start: () async => throw failure,
            stop: () async => events.add('producer'),
          ),
        ],
      );
      await expectLater(runtime.start(), throwsA(same(failure)));
      await runtime.shutdown();
      expect(events, ['producer', 'sink']);
    },
  );
  test('stop attempts every resource and reports named errors', () async {
    final reports = <String>[], events = <String>[];
    final runtime = ApplicationRuntime(
      resources: [
        ApplicationRuntimeResource(
          name: 'hub',
          stop: () async => events.add('hub'),
        ),
        ApplicationRuntimeResource(
          name: 'broken',
          stop: () async => throw StateError('stop failed'),
        ),
      ],
      onFailure: (name, _, _) => reports.add(name),
    );
    await expectLater(runtime.shutdown(), throwsStateError);
    expect(reports, ['broken']);
    expect(events, ['hub']);
  });
}
