import '../../schema/data_input.dart';
import '../../runtime/cancellation.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';
import 'keyboard.dart';
import 'native_input.dart';

const inputMouseButtons = <String>[
  'left',
  'right',
  'middle',
  'mouse4',
  'mouse5',
];

const _pressKeyConfigSchema = DartDataInputSchema(
  label: 'Keyboard action',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Key',
      key: 'key',
      kind: DartDataInputKind.keyboardKey,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Press time (seconds)',
      key: 'duration',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0.1,
    ),
  ],
);

const _keyboardShortcutConfigSchema = DartDataInputSchema(
  label: 'Keyboard shortcut',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Combo',
      key: 'combo',
      kind: DartDataInputKind.keyCombo,
      required: true,
    ),
  ],
);

const _mouseButtonConfigSchema = DartDataInputSchema(
  label: 'Mouse action',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Button',
      key: 'button',
      kind: DartDataInputKind.enumeration,
      options: inputMouseButtons,
      required: true,
      defaultValue: 'left',
    ),
    DartDataInputSchema(
      label: 'Duration (seconds)',
      key: 'duration',
      kind: DartDataInputKind.duration,
      required: true,
      defaultValue: 0.1,
    ),
  ],
);

DartPluginManifest createInputPlugin({InputPlatform? platform}) {
  final inputPlatform = platform ?? const NativeInputPlatform();
  return DartPluginManifest(
    id: 'input',
    name: 'Input',
    actions: [
      DartActionDefinition(
        pluginId: 'input',
        actionId: 'pressKey',
        displayName: 'Simulate Keyboard',
        configSchema: _pressKeyConfigSchema,
        invoke: (config, context) => _pressKey(inputPlatform, config, context),
      ),
      DartActionDefinition(
        pluginId: 'input',
        actionId: 'mouseButton',
        displayName: 'Simulate Mouse',
        configSchema: _mouseButtonConfigSchema,
        invoke: (config, context) =>
            _mouseButton(inputPlatform, config, context),
      ),
    ],
    triggers: [
      DartTriggerDefinition(
        pluginId: 'input',
        triggerId: 'keyboardShortcut',
        displayName: 'Keyboard Shortcut',
        configSchema: _keyboardShortcutConfigSchema,
        listen: () => _listenKeyboardShortcuts(inputPlatform),
        matches: matchesKeyboardShortcut,
      ),
    ],
  );
}

Future<Object?> _pressKey(
  InputPlatform platform,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final key = config['key']?.toString().trim() ?? '';
  final duration = config['duration'] is num
      ? (config['duration'] as num).toDouble()
      : 0.1;
  final virtualKeyCode = virtualKeyCodeForKeyboardKey(key);
  if (virtualKeyCode == null) {
    return {'pressed': false, 'key': key, 'duration': duration};
  }
  final boundedDuration = duration.isFinite && duration > 0 ? duration : 0;
  await platform.simulateKeyDown(virtualKeyCode);
  try {
    if (boundedDuration > 0) {
      await cancellableDelay(
        Duration(microseconds: (boundedDuration * 1000000).round()),
        context.cancellationToken,
      );
    }
  } finally {
    await platform.simulateKeyUp(virtualKeyCode);
  }
  return {'pressed': true, 'key': key, 'duration': duration};
}

Stream<RuntimeMap> _listenKeyboardShortcuts(InputPlatform platform) async* {
  final pressedKeys = <String>{};
  await for (final event in platform.events) {
    final key = keyboardKeyNameForVirtualKey(event.virtualKeyCode);
    if (key == null) continue;
    final normalizedKey = normalizeKeyboardKey(key);
    if (event.pressed) {
      if (!pressedKeys.add(normalizedKey)) continue;
      yield {
        'key': normalizedKey,
        'vkCode': event.virtualKeyCode,
        'pressedKeys': List<String>.unmodifiable(pressedKeys),
      };
    } else {
      pressedKeys.remove(normalizedKey);
    }
  }
}

bool matchesKeyboardShortcut(RuntimeMap config, RuntimeMap payload) {
  final combo = config['combo'];
  final pressedKeys = payload['pressedKeys'];
  final eventKey = payload['key'];
  if (combo is! List || pressedKeys is! List || eventKey is! String) {
    return false;
  }
  final normalizedCombo = combo
      .whereType<String>()
      .map(normalizeKeyboardKey)
      .toSet();
  final normalizedPressedKeys = pressedKeys
      .whereType<String>()
      .map(normalizeKeyboardKey)
      .toSet();
  return normalizedCombo.isNotEmpty &&
      normalizedCombo.contains(normalizeKeyboardKey(eventKey)) &&
      normalizedCombo.every(normalizedPressedKeys.contains);
}

Future<Object?> _mouseButton(
  InputPlatform platform,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final button = config['button']?.toString().trim().toLowerCase() ?? '';
  final duration = config['duration'] is num
      ? (config['duration'] as num).toDouble()
      : 0.1;
  if (!inputMouseButtons.contains(button)) {
    return {'pressed': false, 'button': button, 'duration': duration};
  }

  final boundedDuration = duration.isFinite && duration > 0 ? duration : 0;
  await platform.simulateMouseDown(button);
  try {
    if (boundedDuration > 0) {
      await cancellableDelay(
        Duration(microseconds: (boundedDuration * 1000000).round()),
        context.cancellationToken,
      );
    }
  } finally {
    await platform.simulateMouseUp(button);
  }
  return {'pressed': true, 'button': button, 'duration': duration};
}
