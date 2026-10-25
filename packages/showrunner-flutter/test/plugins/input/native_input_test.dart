import 'package:showrunner_flutter/plugins/input/bootstrap.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/plugins/input/keyboard.dart';
import 'package:showrunner_flutter/plugins/input/contracts.dart';
import 'package:showrunner_flutter/plugins/input/manifest.dart';
import 'package:showrunner_flutter/plugins/input/native_input.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_module.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import '../../support/graph_fixtures.dart';
import 'package:showrunner_flutter/schema/profile.dart';

void main() {
  for (final supported in [true, false]) {
    test(
      'input registration owns hooks only on supported platforms: $supported',
      () async {
        final platform = _FakeInputPlatform();
        final registry = DartPluginRegistry();
        registerConfiguredInput(
          registry,
          platform: platform,
          nativeHooksSupported: supported,
        );
        await registry.initialize();
        await registry.start();
        expect(platform.calls, supported ? ['start-events'] : isEmpty);
        final health = await registry.checkHealthDetailsId(
          const PluginId('input'),
        );
        expect(
          health.status,
          supported
              ? DartPluginHealthStatus.ready
              : DartPluginHealthStatus.unavailable,
        );
        if (!supported) expect(health.message, contains('Windows-only'));
        await registry.close();
        expect(
          platform.calls,
          supported ? ['start-events', 'stop-events'] : isEmpty,
        );
      },
    );
  }
  test('decodes input actions and shortcuts into typed contracts', () {
    final plugin = createInputPlugin();
    final key = plugin.actions
        .firstWhere((action) => action.actionId.value == 'pressKey')
        .decodeConfig({'key': 'A', 'duration': 0.2});
    expect(key, isA<InputPressKeyConfig>());
    expect((key as InputPressKeyConfig).duration, 0.2);

    final shortcut = plugin.triggers.single.decodeConfig({
      'combo': ['RightControl', 'A'],
    });
    expect(shortcut, isA<InputKeyboardShortcutConfig>());
    expect((shortcut as InputKeyboardShortcutConfig).combo, [
      'LeftControl',
      'A',
    ]);
  });

  test('parses native keyboard events and ignores malformed payloads', () {
    expect(
      InputKeyEvent.tryParse({'type': 'key-pressed', 'vkCode': 65}),
      const InputKeyEvent(virtualKeyCode: 65, pressed: true),
    );
    expect(
      InputKeyEvent.tryParse({'type': 'key-released', 'vkCode': 65}),
      const InputKeyEvent(virtualKeyCode: 65, pressed: false),
    );
    expect(InputKeyEvent.tryParse({'type': 'mouse', 'vkCode': 1}), isNull);
    expect(InputKeyEvent.tryParse({'type': 'key-pressed'}), isNull);
    expect(
      InputKeyEvent.tryParse({'type': 'key-pressed', 'vkCode': 256}),
      isNull,
    );
    expect(
      InputKeyEvent.tryParse({'type': 'key-pressed', 'vkCode': 1.5}),
      isNull,
    );
  });

  test('maps supported keys to Windows virtual-key codes', () {
    expect(virtualKeyCodeForKeyboardKey('F10'), 0x79);
    expect(virtualKeyCodeForKeyboardKey('F24'), 0x87);
    expect(keyboardKeyNameForVirtualKey(0x79), 'F10');
    expect(keyboardKeyNameForVirtualKey(0x87), 'F24');
    expect(keyboardKeyNameForVirtualKey(0xffff), isNull);
  });

  test(
    'pressKey routes the mapped virtual key and always releases it',
    () async {
      final platform = _FakeInputPlatform();
      final plugin = createInputPlugin(platform: platform);

      final result = await plugin.actions
          .firstWhere((action) => action.actionId.value == 'pressKey')
          .invokeFromRuntime({'key': 'A', 'duration': 0}, EvaluationContext());

      expect(platform.calls, ['key-down:65', 'key-up:65']);
      expect(result, {'pressed': true, 'key': 'A', 'duration': 0});
    },
  );

  test('mouseButton routes the selected button and releases it', () async {
    final platform = _FakeInputPlatform();
    final plugin = createInputPlugin(platform: platform);

    final result = await plugin.actions
        .firstWhere((action) => action.actionId.value == 'mouseButton')
        .invokeFromRuntime({
          'button': 'mouse4',
          'duration': 0,
        }, EvaluationContext());

    expect(platform.calls, ['mouse-down:mouse4', 'mouse-up:mouse4']);
    expect(result, {'pressed': true, 'button': 'mouse4', 'duration': 0});
  });

  test('mouseButton rejects unknown buttons without native calls', () async {
    final platform = _FakeInputPlatform();
    final plugin = createInputPlugin(platform: platform);

    final result = await plugin.actions
        .firstWhere((action) => action.actionId.value == 'mouseButton')
        .invokeFromRuntime({
          'button': 'sideways',
          'duration': 0.1,
        }, EvaluationContext());

    expect(platform.calls, isEmpty);
    expect(result, {'pressed': false, 'button': 'sideways', 'duration': 0.1});
  });

  test('pressKey cancellation releases the held key', () async {
    final platform = _FakeInputPlatform();
    final plugin = createInputPlugin(platform: platform);
    final token = DartCancellationToken(id: 'input-cancel');
    final action = plugin.actions.firstWhere(
      (action) => action.actionId.value == 'pressKey',
    );

    final execution = action.invokeFromRuntime({
      'key': 'A',
      'duration': 10,
    }, EvaluationContext(cancellationToken: token));
    await Future<void>.delayed(Duration.zero);
    token.cancel();

    await expectLater(execution, throwsA(isA<DartCancelledException>()));
    expect(platform.calls, ['key-down:65', 'key-up:65']);
  });

  test('configured input lifecycle starts and stops global events', () async {
    final platform = _FakeInputPlatform();
    final module = ManifestDartPluginModule(
      createInputPlugin(platform: platform),
      onStart: platform.startEvents,
      onStop: platform.stopEvents,
    );

    await module.start();
    expect(platform.calls, ['start-events']);

    await module.stop();
    expect(platform.calls, ['start-events', 'stop-events']);
  });

  test('input manifest exposes the mouse action schema', () {
    final mouse = createInputPlugin().actions.firstWhere(
      (action) => action.actionId.value == 'mouseButton',
    );

    expect(mouse.configSchema?.fields.map((field) => field.key), [
      'button',
      'duration',
    ]);
    expect(mouse.configSchema?.fields.first.options, inputMouseButtons);
    expect(mouse.configSchema?.fields.first.defaultValue, 'left');
    expect(mouse.configSchema?.fields.last.kind, DartDataInputKind.duration);
  });

  test(
    'keyboard shortcut matching honors normalized modifiers and key state',
    () {
      expect(
        matchesKeyboardShortcut(
          {
            'combo': ['RightControl', 'A'],
          },
          {
            'key': 'A',
            'pressedKeys': ['LeftControl', 'A', 'B'],
          },
        ),
        isTrue,
      );
      expect(
        matchesKeyboardShortcut(
          {
            'combo': ['LeftControl', 'A'],
          },
          {
            'key': 'A',
            'pressedKeys': ['A'],
          },
        ),
        isFalse,
      );
    },
  );

  test('profile watch filters configured keyboard shortcuts', () async {
    final executionCompleted = Completer<void>();
    final platform = _FakeInputPlatform(
      events: Stream<InputKeyEvent>.fromIterable([
        const InputKeyEvent(virtualKeyCode: 17, pressed: true),
        const InputKeyEvent(virtualKeyCode: 65, pressed: true),
        const InputKeyEvent(virtualKeyCode: 65, pressed: false),
        const InputKeyEvent(virtualKeyCode: 17, pressed: false),
        const InputKeyEvent(virtualKeyCode: 66, pressed: true),
      ]),
    );
    var executions = 0;
    final registry = DartPluginRegistry()
      ..register(createInputPlugin(platform: platform))
      ..register(
        DartPluginManifest(
          id: PluginId('test'),
          name: 'Test',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('test'),
              actionId: ActionId('record'),
              invoke: (config, context) async {
                executions++;
                executionCompleted.complete();
                return null;
              },
            ),
          ],
        ),
      );
    final profile = ShowRunnerProfile(
      name: 'Shortcuts',
      activationMode: 'always',
      triggers: [
        {
          'id': 'keyboard-shortcut',

          'config': {
            'combo': ['LeftControl', 'A'],
          },
          'automation': eventFixture(
            id: 'keyboard',
            plugin: 'input',
            trigger: 'keyboardShortcut',
            config: {
              'combo': ['LeftControl', 'A'],
            },
            nodes: [actionFixture('record')],
            next: 'record',
          ).toJson(),
        },
      ],
      activationCondition: const {},
      activationAutomation: AutomationDocument.empty(),
      deactivationAutomation: AutomationDocument.empty(),
    );
    final runtime = DartProfileRuntime(registry: registry);
    await runtime.activate('shortcuts', profile);
    final session = runtime.watch('shortcuts', profile);
    await executionCompleted.future.timeout(const Duration(seconds: 1));
    expect(executions, 1);
    await session.dispose();
    expect(executions, 1);
  });
}

final class _FakeInputPlatform implements InputPlatform {
  _FakeInputPlatform({Stream<InputKeyEvent>? events})
    : events = events ?? const Stream<InputKeyEvent>.empty();

  @override
  final Stream<InputKeyEvent> events;

  final calls = <String>[];

  @override
  Future<void> simulateKeyDown(int virtualKeyCode) async {
    calls.add('key-down:$virtualKeyCode');
  }

  @override
  Future<void> simulateKeyUp(int virtualKeyCode) async {
    calls.add('key-up:$virtualKeyCode');
  }

  @override
  Future<void> simulateMouseDown(String button) async {
    calls.add('mouse-down:$button');
  }

  @override
  Future<void> simulateMouseUp(String button) async {
    calls.add('mouse-up:$button');
  }

  @override
  Future<void> startEvents() async {
    calls.add('start-events');
  }

  @override
  Future<void> stopEvents() async {
    calls.add('stop-events');
  }

  @override
  Future<bool> isKeyDown(int virtualKeyCode) async => false;
}
