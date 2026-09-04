import 'package:flutter_tts/flutter_tts.dart';

import '../../runtime/expression.dart';

final class TtsSpeechRequest {
  const TtsSpeechRequest({
    required this.text,
    this.voiceProvider,
    this.voiceName,
    this.voiceLocale,
    this.volume = 1,
    this.pitch = 1,
    this.rate = 0.5,
  });

  final String text;
  final String? voiceProvider;
  final String? voiceName;
  final String? voiceLocale;
  final double volume;
  final double pitch;
  final double rate;
}

final class TtsSpeechResult {
  const TtsSpeechResult({required this.spoken, required this.text});

  final bool spoken;
  final String text;

  RuntimeMap toMap() => {'spoken': spoken, 'text': text};
}

abstract interface class TtsSpeechService {
  Future<TtsSpeechResult> speak(TtsSpeechRequest request);
}

final class FlutterTtsSpeechService implements TtsSpeechService {
  FlutterTtsSpeechService({this._client});

  FlutterTts? _client;

  FlutterTts get _tts => _client ??= FlutterTts();

  @override
  Future<TtsSpeechResult> speak(TtsSpeechRequest request) async {
    if (request.text.trim().isEmpty) {
      return TtsSpeechResult(spoken: false, text: request.text);
    }

    final tts = _tts;
    await tts.awaitSpeakCompletion(true);
    await _configureVoice(tts, request);
    await _requireSuccess(tts.setVolume(request.volume), 'volume');
    await _requireSuccess(tts.setPitch(request.pitch), 'pitch');
    await _requireSuccess(tts.setSpeechRate(request.rate), 'rate');
    await _requireSuccess(tts.speak(request.text), 'speech');
    return TtsSpeechResult(spoken: true, text: request.text);
  }

  Future<void> _configureVoice(FlutterTts tts, TtsSpeechRequest request) async {
    final provider = request.voiceProvider?.trim() ?? '';
    final name = request.voiceName?.trim() ?? '';
    final locale = request.voiceLocale?.trim() ?? '';
    if (provider.isEmpty && name.isEmpty && locale.isEmpty) return;

    if (name.isNotEmpty && locale.isNotEmpty) {
      await _requireSuccess(
        tts.setVoice({'name': name, 'locale': locale}),
        'voice',
      );
      return;
    }

    if (provider == 'system') return;
    final voices = _voiceMaps(await tts.getVoices);
    final selected = _findVoice(voices, provider, name, locale);
    if (selected != null) {
      final selectedName = selected['name']?.toString().trim() ?? '';
      final selectedLocale = selected['locale']?.toString().trim() ?? '';
      if (selectedName.isNotEmpty && selectedLocale.isNotEmpty) {
        await _requireSuccess(
          tts.setVoice({'name': selectedName, 'locale': selectedLocale}),
          'voice',
        );
        return;
      }
    }

    final systemLocale = _systemLocale(provider);
    if (systemLocale != null) {
      await _requireSuccess(tts.setLanguage(systemLocale), 'language');
      return;
    }

    throw StateError('TTS voice provider is not available: $provider');
  }

  List<Map<String, dynamic>> _voiceMaps(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((voice) => Map<String, dynamic>.from(voice))
            .toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic>? _findVoice(
    List<Map<String, dynamic>> voices,
    String provider,
    String name,
    String locale,
  ) {
    final expected = provider.startsWith('system.')
        ? provider.substring('system.'.length)
        : provider;
    final normalizedExpected = expected.toLowerCase();
    for (final voice in voices) {
      final identifier = voice['identifier']?.toString().toLowerCase();
      final voiceId = voice['id']?.toString().toLowerCase();
      final voiceName = voice['name']?.toString().toLowerCase();
      final voiceLocale = voice['locale']?.toString().toLowerCase();
      if (name.isNotEmpty &&
          voiceName == name.toLowerCase() &&
          (locale.isEmpty || voiceLocale == locale.toLowerCase())) {
        return voice;
      }
      if (locale.isNotEmpty && voiceLocale == locale.toLowerCase()) {
        return voice;
      }
      if (normalizedExpected.isNotEmpty &&
          (identifier == normalizedExpected ||
              voiceId == normalizedExpected ||
              voiceName == normalizedExpected ||
              voiceLocale == normalizedExpected)) {
        return voice;
      }
    }
    return null;
  }

  String? _systemLocale(String provider) {
    if (!provider.startsWith('system.')) return null;
    final locale = provider.substring('system.'.length).replaceAll('_', '-');
    final isLocale = RegExp(
      r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})+$',
    ).hasMatch(locale);
    return isLocale ? locale : null;
  }

  Future<void> _requireSuccess(
    Future<dynamic> operation,
    String setting,
  ) async {
    final result = await operation;
    if (!_isSuccess(result)) {
      throw StateError('TTS $setting configuration failed.');
    }
  }
}

bool _isSuccess(dynamic value) {
  if (value == null || value == true) return true;
  if (value is num) return value != 0;
  return value.toString() != '0' && value.toString().toLowerCase() != 'false';
}
