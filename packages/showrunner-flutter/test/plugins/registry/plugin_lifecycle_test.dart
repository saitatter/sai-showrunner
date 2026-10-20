import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_lifecycle.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

const _id = PluginId('sample');

void main() {
  test(
    'enabling a skipped module starts once; disabling preserves shared connections',
    () async {
      var starts = 0, stops = 0;
      final registry = DartPluginRegistry()
        ..register(
          const DartPluginManifest(id: _id, name: 'Sample'),
          onStart: () async => starts++,
          onStop: () async => stops++,
        );
      registry.setPluginEnabledId(_id, false);
      await registry.initialize();
      expect(registry.lifecycleOf(_id), PluginLifecycleState.initialized);
      await registry.start();
      expect(registry.lifecycleOf(_id), PluginLifecycleState.disabled);
      final persisted = <bool>[];
      Future<void> persist(bool value) async => persisted.add(value);
      await registry.setEnabled(_id, true, persist: persist);
      await registry.setEnabled(_id, false, persist: persist);
      expect(registry.lifecycleOf(_id), PluginLifecycleState.running);
      expect(registry.enablePolicyOf(_id), PluginEnablePolicy.automationOnly);
      expect(registry.isPluginEnabledId(_id), isFalse);
      expect(registry.findPlugin('sample'), isNotNull);
      expect(stops, 0);
      await registry.setEnabled(_id, true, persist: persist);
      await registry.setEnabled(_id, true, persist: persist);
      expect(starts, 1);
      expect(persisted, [true, false, true]);
      await Future.wait([registry.close(), registry.close()]);
      expect(stops, 1);
      expect(registry.lifecycleOf(_id), PluginLifecycleState.stopped);
    },
  );

  test(
    'persistence failure keeps published policy and does not poison the queue',
    () async {
      final registry = DartPluginRegistry()
        ..register(const DartPluginManifest(id: _id, name: 'Sample'));
      final failure = StateError('Disk unavailable');
      await expectLater(
        registry.setEnabled(_id, false, persist: (_) async => throw failure),
        throwsA(same(failure)),
      );
      expect(registry.isPluginEnabledId(_id), isTrue);
      await registry.setEnabled(_id, false, persist: (_) async {});
      expect(registry.isPluginEnabledId(_id), isFalse);
      await registry.close();
    },
  );

  test(
    'failed first enable rolls persistence back and releases partial resources once',
    () async {
      var starts = 0, stops = 0;
      final failure = StateError('Provider start failed');
      final registry = DartPluginRegistry()
        ..register(
          const DartPluginManifest(id: _id, name: 'Sample'),
          onStart: () async {
            starts++;
            throw failure;
          },
          onStop: () async => stops++,
        );
      registry.setPluginEnabledId(_id, false);
      await registry.initialize();
      await registry.start();
      final writes = <bool>[];
      await expectLater(
        registry.setEnabled(
          _id,
          true,
          persist: (value) async => writes.add(value),
        ),
        throwsA(same(failure)),
      );
      expect(writes, [true, false]);
      expect(registry.isPluginEnabledId(_id), isFalse);
      expect(registry.lifecycleOf(_id), PluginLifecycleState.failed);
      expect(registry.lifecycleError(_id), same(failure));
      await expectLater(
        registry.setEnabled(_id, true, persist: (_) async {}),
        throwsStateError,
      );
      await registry.close();
      expect(starts, 1);
      expect(stops, 1);
    },
  );

  test('rollback failure preserves both errors for diagnostics', () async {
    final startError = StateError('Start failed'),
        diskError = StateError('Rollback failed');
    final registry = DartPluginRegistry()
      ..register(
        const DartPluginManifest(id: _id, name: 'Sample'),
        onStart: () async => throw startError,
      );
    registry.setPluginEnabledId(_id, false);
    await registry.start();
    await expectLater(
      registry.setEnabled(
        _id,
        true,
        persist: (value) async {
          if (!value) throw diskError;
        },
      ),
      throwsA(
        isA<PluginPolicyTransactionError>()
            .having((error) => error.cause, 'original cause', same(startError))
            .having(
              (error) => error.rollbackError,
              'rollback error',
              same(diskError),
            ),
      ),
    );
    await registry.close();
  });

  test(
    'opposing toggles serialize and publish only after persistence',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final writes = <bool>[];
      final registry = DartPluginRegistry()
        ..register(const DartPluginManifest(id: _id, name: 'Sample'));
      final disabling = registry.setEnabled(
        _id,
        false,
        persist: (value) async {
          writes.add(value);
          entered.complete();
          await release.future;
        },
      );
      await entered.future;
      final enabling = registry.setEnabled(
        _id,
        true,
        persist: (value) async => writes.add(value),
      );
      expect(writes, [false]);
      expect(registry.isPluginEnabledId(_id), isTrue);
      release.complete();
      await Future.wait([disabling, enabling]);
      expect(writes, [false, true]);
      expect(registry.isPluginEnabledId(_id), isTrue);
      await registry.close();
    },
  );

  test(
    'shutdown waits for policy rollback before stopping owned modules',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final events = <String>[];
      final registry = DartPluginRegistry()
        ..register(
          const DartPluginManifest(id: _id, name: 'Sample'),
          onStop: () async => events.add('stop'),
        );
      final changing = registry.setEnabled(
        _id,
        false,
        persist: (value) async {
          events.add('persist:$value');
          if (!value) {
            entered.complete();
            await release.future;
          }
        },
      );
      final failure = expectLater(changing, throwsStateError);
      await entered.future;
      final closing = registry.close();
      expect(events, ['persist:false']);
      release.complete();
      await Future.wait([failure, closing]);
      expect(events, ['persist:false', 'persist:true', 'stop']);
      expect(registry.isPluginEnabledId(_id), isTrue);
    },
  );

  test(
    'late health results cannot report healthy after disable or close',
    () async {
      final pending = Completer<bool>();
      final registry = DartPluginRegistry()
        ..register(
          const DartPluginManifest(id: _id, name: 'Sample'),
          onHealthCheck: () => pending.future,
        );
      final checking = registry.checkHealthId(_id);
      registry.setPluginEnabledId(_id, false);
      pending.complete(true);
      expect(await checking, isFalse);
      await registry.close();
      expect(await registry.checkHealthId(_id), isFalse);
    },
  );
}
