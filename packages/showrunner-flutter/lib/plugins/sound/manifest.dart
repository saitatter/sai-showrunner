import '../../runtime/expression.dart';
import '../../components/data_inputs/data_input.dart';
import '../registry/plugin_registry.dart';
import 'output.dart';
import 'tts_runtime.dart';
import 'windows_audio.dart';

const _soundSchema = DartDataInputSchema(
  label: 'Sound',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Output',
      key: 'output',
      kind: DartDataInputKind.resource,
      resourceType: 'SoundOutput',
    ),
    DartDataInputSchema(
      label: 'Sound file',
      key: 'sound',
      kind: DartDataInputKind.filePath,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Volume (0-100)',
      key: 'volume',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 100,
    ),
    DartDataInputSchema(
      label: 'Start timestamp',
      key: 'startTime',
      kind: DartDataInputKind.duration,
      required: true,
      defaultValue: 0,
    ),
    DartDataInputSchema(
      label: 'End timestamp',
      key: 'endTime',
      kind: DartDataInputKind.duration,
    ),
  ],
);

const _speakTtsSchema = DartDataInputSchema(
  label: 'Text to Speech',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Text',
      key: 'text',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Output',
      key: 'output',
      kind: DartDataInputKind.resource,
      resourceType: 'SoundOutput',
    ),
    DartDataInputSchema(
      label: 'Voice provider',
      key: 'voiceProvider',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Volume (0-100)',
      key: 'volume',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 100,
    ),
    DartDataInputSchema(
      label: 'Pitch (-10 to 10)',
      key: 'pitch',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0,
    ),
    DartDataInputSchema(
      label: 'Rate (-10 to 10)',
      key: 'rate',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0,
    ),
  ],
);

final class _SoundDependencies {
  const _SoundDependencies({
    required this.tts,
    required this.ttsFile,
    required this.outputs,
  });

  final TtsSpeechService tts;
  final TtsFileSynthesisService? ttsFile;
  final SoundOutputRegistry outputs;
}

DartPluginManifest createSoundPlugin({
  TtsSpeechService? ttsService,
  TtsFileSynthesisService? ttsFileService,
  SoundOutputRegistry? soundOutputs,
}) {
  final dependencies = _SoundDependencies(
    tts: ttsService ?? FlutterTtsSpeechService(),
    ttsFile: ttsFileService ?? createDefaultTtsFileSynthesisService(),
    outputs: soundOutputs ?? createDefaultSoundOutputRegistry(),
  );
  return DartPluginManifest(
    id: 'sound',
    name: 'Sound & TTS',
    actions: [
      DartActionDefinition(
        pluginId: 'sound',
        actionId: 'sound',
        displayName: 'Play Sound',
        configSchema: _soundSchema,
        invoke: (config, context) =>
            _playSound(config, context, dependencies.outputs),
      ),
      DartActionDefinition(
        pluginId: 'sound',
        actionId: 'speakTTS',
        displayName: 'Speak Text-to-Speech',
        configSchema: _speakTtsSchema,
        invoke: (config, context) => _speakTTS(
          config,
          context,
          dependencies.tts,
          dependencies.ttsFile,
          dependencies.outputs,
        ),
      ),
      DartActionDefinition(
        pluginId: 'sound',
        actionId: 'tts',
        displayName: 'Text to Speech',
        configSchema: _speakTtsSchema,
        invoke: (config, context) => _speakTTS(
          config,
          context,
          dependencies.tts,
          dependencies.ttsFile,
          dependencies.outputs,
        ),
      ),
    ],
  );
}

Future<Object?> _playSound(
  RuntimeMap config,
  EvaluationContext context,
  SoundOutputRegistry outputs,
) async {
  final file = _firstText(<Object?>[config['sound'], config['file']]);
  if (file == null) return {'played': false};

  final result = await outputs.playFile(
    outputId: _resourceId(config['output']),
    file: file,
    startSec: _soundNumber(config['startTime'], 0).clamp(0, double.infinity),
    endSec: _soundNumber(config['endTime'], double.infinity),
    volume: _soundNumber(config['volume'], 100),
  );
  return {'played': result, 'sound': file};
}

String? _resourceId(Object? value) {
  if (value is String) return _firstText([value]);
  if (value is Map) {
    return _firstText(<Object?>[
      value['id'],
      value['value'],
      if (value['resource'] is Map) (value['resource'] as Map)['id'],
    ]);
  }
  return null;
}

double _soundNumber(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

Future<Object?> _speakTTS(
  RuntimeMap config,
  EvaluationContext context,
  TtsSpeechService service,
  TtsFileSynthesisService? fileService,
  SoundOutputRegistry outputs,
) async {
  final text = config['text']?.toString() ?? '';
  if (text.trim().isEmpty) return {'spoken': false, 'text': text};

  final rawVoice = config['voice'];
  final voiceConfig = rawVoice is Map && rawVoice['config'] is Map
      ? Map<String, dynamic>.from(rawVoice['config'] as Map)
      : rawVoice is Map
      ? Map<String, dynamic>.from(rawVoice)
      : const <String, dynamic>{};
  final providerConfig = config['providerConfig'] is Map
      ? Map<String, dynamic>.from(config['providerConfig'] as Map)
      : voiceConfig['providerConfig'] is Map
      ? Map<String, dynamic>.from(voiceConfig['providerConfig'] as Map)
      : const <String, dynamic>{};
  final voiceProvider = _firstText(<Object?>[
    config['voiceProvider'],
    voiceConfig['voiceProvider'],
    rawVoice is String ? rawVoice : null,
  ]);
  final voiceName = _firstText(<Object?>[
    config['voiceName'],
    voiceConfig['name'],
    rawVoice is Map ? rawVoice['name'] : null,
  ]);
  final voiceLocale = _firstText(<Object?>[
    config['voiceLocale'],
    voiceConfig['locale'],
    rawVoice is Map ? rawVoice['locale'] : null,
  ]);
  final pitch = _legacyPitch(providerConfig['pitch'] ?? config['pitch']);
  final rate = _legacyRate(providerConfig['rate'] ?? config['rate']);
  final volume = _legacyVolume(config['volume']);
  final request = TtsSpeechRequest(
    text: text,
    voiceProvider: voiceProvider,
    voiceName: voiceName,
    voiceLocale: voiceLocale,
    volume: volume,
    pitch: pitch,
    rate: rate,
  );
  final generatedFile = await fileService?.synthesizeToFile(request);
  if (generatedFile != null) {
    final played = await outputs.playFile(
      outputId: _resourceId(config['output']),
      file: generatedFile,
      volume: volume * 100,
    );
    return {'spoken': played, 'text': text, 'file': generatedFile};
  }
  final result = await service.speak(request);
  return result.toMap();
}

String? _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

double _legacyVolume(Object? value) =>
    ((value is num ? value.toDouble() : double.tryParse('$value') ?? 100) / 100)
        .clamp(0, 1)
        .toDouble();

double _legacyRate(Object? value) {
  final rate = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  return ((rate.clamp(-10, 10) + 10) / 20).clamp(0, 1).toDouble();
}

double _legacyPitch(Object? value) {
  final pitch = value is num
      ? value.toDouble()
      : double.tryParse('$value') ?? 0;
  final normalized = 1 + pitch.clamp(-10, 10) / 10;
  return normalized.clamp(0.5, 2).toDouble();
}
