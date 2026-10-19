import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';
import 'keyboard.dart';

final class InputPressKeyConfig {
  const InputPressKeyConfig({this.key, this.duration = 0.1});

  factory InputPressKeyConfig.fromRuntime(RuntimeMap value) =>
      InputPressKeyConfig(
        key: _string(value['key']),
        duration: value['duration'] is num ? value['duration'] as num : 0.1,
      );

  final String? key;
  final num duration;

  RuntimeMap toRuntime() => {if (key != null) 'key': key, 'duration': duration};
}

final class InputMouseButtonConfig {
  const InputMouseButtonConfig({this.button = 'left', this.duration = 0.1});

  factory InputMouseButtonConfig.fromRuntime(RuntimeMap value) =>
      InputMouseButtonConfig(
        button: _string(value['button']) ?? 'left',
        duration: value['duration'] is num ? value['duration'] as num : 0.1,
      );

  final String button;
  final num duration;

  RuntimeMap toRuntime() => {'button': button, 'duration': duration};
}

final class InputKeyboardShortcutConfig {
  const InputKeyboardShortcutConfig({this.combo = const []});

  factory InputKeyboardShortcutConfig.fromRuntime(RuntimeMap value) =>
      InputKeyboardShortcutConfig(
        combo: value['combo'] is List
            ? (value['combo'] as List)
                  .whereType<String>()
                  .map(normalizeKeyboardKey)
                  .toList()
            : const <String>[],
      );

  final List<String> combo;

  RuntimeMap toRuntime() => {'combo': combo};
}

final class InputKeyboardShortcutEvent {
  const InputKeyboardShortcutEvent({
    this.key,
    this.vkCode,
    this.pressedKeys = const [],
  });

  factory InputKeyboardShortcutEvent.fromRuntime(RuntimeMap value) =>
      InputKeyboardShortcutEvent(
        key: _string(value['key']),
        vkCode: _integer(value['vkCode']),
        pressedKeys: value['pressedKeys'] is List
            ? (value['pressedKeys'] as List).whereType<String>().toList()
            : const [],
      );

  final String? key;
  final int? vkCode;
  final List<String> pressedKeys;

  RuntimeMap toRuntime() => {
    if (key != null) 'key': key,
    if (vkCode != null) 'vkCode': vkCode,
    'pressedKeys': pressedKeys,
  };
}

final class InputConfigCodec<C> implements PluginConfigCodec<C> {
  const InputConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final inputPressKeyConfigCodec = InputConfigCodec(
  InputPressKeyConfig.fromRuntime,
  (InputPressKeyConfig value) => value.toRuntime(),
);
final inputMouseButtonConfigCodec = InputConfigCodec(
  InputMouseButtonConfig.fromRuntime,
  (InputMouseButtonConfig value) => value.toRuntime(),
);
final inputKeyboardShortcutConfigCodec = InputConfigCodec(
  InputKeyboardShortcutConfig.fromRuntime,
  (InputKeyboardShortcutConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
