import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/input/keyboard.dart';
import 'package:showrunner_flutter/plugins/input/manifest.dart';
import 'package:showrunner_flutter/plugins/input/native_input.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/profile.dart';

void main() {
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
    expect(InputKeyEvent.tryParse({'type': 'key-pressed', 'vkCode': 256}), isNull);
    expect(InputKeyEvent.tryParse({'type': 'key-pressed', 'vkCode': 1.5}), isNull);
  });

  test('maps legacy keys to Windows virtual-key codes', () {
    expect(virtualKeyCodeForKeyboardKey('F10'), 0x79);
    expect(virtualKeyCodeForKeyboardKey('F24'), 0x87);
    expect(keyboardKeyNameForVirtualKey(0x79), 'F10');
    expect(keyboardKeyNameForVirtualKey(0x87), 'F24');
    expect(keyboardKeyNameForVirtualKey(0xffff), isNull);
  });

  test('pressKey routes the mapped virtual key and always releases it', () async {
    final platform = _FakeInputPlatform();
    final plugin = createInputPlugin(platform: platform);

    final result = await plugin.actions.single.invoke(
      {'key': 'A', 'duration': 0},
      EvaluationContext(),
    );

    expect(platform.calls, ['key-down:65', 'key-up:65']);
    expect(result, {'pressed': true, 'key': 'A', 'duration': 0});
  });

  test('keyboard shortcut matching honors normalized modifiers and key state', () {
    expect(
      matchesKeyboardShortcut(
        {'combo': ['RightControl', 'A']},
        {
          'key': 'A',
          'pressedKeys': ['LeftControl', 'A', 'B'],
        },
      ),
      isTrue,
    );
    expect(
      matchesKeyboardShortcut(
        {'combo': ['LeftControl', 'A']},
        {'key': 'A', 'pressedKeys': ['A']},
      ),
      isFalse,
    );
  });

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
          id: 'test',
          name: 'Test',
          actions: [
            DartActionDefinition(
              pluginId: 'test',
              actionId: 'record',
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
          'plugin': 'input',
          'trigger': 'keyboardShortcut',
          'config': {'combo': ['LeftControl', 'A']},
          'graph': {
            'nodes': [
              {
                'id': 'record',
                'type': 'action',
                'plugin': 'test',
                'action': 'record',
              },
            ],
            'entryNodeId': 'record',
          },
        },
      ],
      activationCondition: const {},
      activationAutomation: AutomationData(),
      deactivationAutomation: AutomationData(),
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
  Future<void> startEvents() async {}

  @override
  Future<void> stopEvents() async {}

  @override
  Future<bool> isKeyDown(int virtualKeyCode) async => false;
}