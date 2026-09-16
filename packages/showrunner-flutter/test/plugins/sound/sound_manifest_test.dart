import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/sound/contracts.dart';
import 'package:showrunner_flutter/plugins/sound/manifest.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';

void main() {
  test('decodes sound and TTS actions into typed configurations', () {
    final registry = DartPluginRegistry()
      ..register(createSoundPlugin(soundOutputs: SoundOutputRegistry()));

    expect(
      registry.findAction('sound', 'sound')?.decodeConfig({
        'sound': 'alert.wav',
        'volume': '65',
      }),
      isA<SoundPlaybackConfig>(),
    );
    expect(
      registry.findAction('sound', 'tts')?.decodeConfig({
        'text': 'hello',
        'pitch': 2,
      }),
      isA<TtsActionConfig>(),
    );
  });
}
