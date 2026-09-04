import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/sound/manifest.dart';
import 'package:showrunner_flutter/plugins/sound/tts_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'maps legacy TTS resource configuration into a speech request',
    () async {
      final service = _RecordingSpeechService();
      final registry = DartPluginRegistry()
        ..register(createSoundPlugin(ttsService: service));

      final result = await registry.invokeAction('sound', 'speakTTS', {
        'text': 'Hello from ShowRunner',
        'voice': {
          'config': {
            'voiceProvider': 'system.voice-1',
            'providerConfig': {'pitch': 2, 'rate': -3},
          },
        },
        'volume': 75,
      });

      expect(result, {'spoken': true, 'text': 'Hello from ShowRunner'});
      expect(service.requests, hasLength(1));
      final request = service.requests.single;
      expect(request.voiceProvider, 'system.voice-1');
      expect(request.volume, closeTo(0.75, 0.0001));
      expect(request.pitch, closeTo(1.2, 0.0001));
      expect(request.rate, closeTo(0.35, 0.0001));
    },
  );

  test('does not invoke the speech service for blank text', () async {
    final service = _RecordingSpeechService();
    final registry = DartPluginRegistry()
      ..register(createSoundPlugin(ttsService: service));

    final result = await registry.invokeAction('sound', 'speakTTS', {
      'text': '  ',
    });

    expect(result, {'spoken': false, 'text': '  '});
    expect(service.requests, isEmpty);
  });

  test(
    'configures a system voice by identifier and forwards speech settings',
    () async {
      final client = _FakeFlutterTts([
        {'identifier': 'voice-1', 'name': 'Narrator', 'locale': 'en-US'},
      ]);
      final service = FlutterTtsSpeechService(client: client);

      final result = await service.speak(
        const TtsSpeechRequest(
          text: 'Hello',
          voiceProvider: 'system.voice-1',
          volume: 0.75,
          pitch: 1.2,
          rate: 0.35,
        ),
      );

      expect(result.toMap(), {'spoken': true, 'text': 'Hello'});
      expect(client.calls, [
        'await:true',
        'voice:Narrator/en-US',
        'volume:0.75',
        'pitch:1.2',
        'rate:0.35',
        'speak:Hello',
      ]);
    },
  );

  test(
    'falls back to a system locale when the voice catalog has no match',
    () async {
      final client = _FakeFlutterTts(const []);
      final service = FlutterTtsSpeechService(client: client);

      await service.speak(
        const TtsSpeechRequest(text: 'Hello', voiceProvider: 'system.en-US'),
      );

      expect(client.calls, contains('language:en-US'));
      expect(client.calls, contains('speak:Hello'));
    },
  );

  test('rejects an unavailable voice provider before speaking', () async {
    final client = _FakeFlutterTts(const []);
    final service = FlutterTtsSpeechService(client: client);

    await expectLater(
      service.speak(
        const TtsSpeechRequest(text: 'Hello', voiceProvider: 'system.missing'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(client.calls, isNot(contains('speak:Hello')));
  });
}

final class _RecordingSpeechService implements TtsSpeechService {
  final requests = <TtsSpeechRequest>[];

  @override
  Future<TtsSpeechResult> speak(TtsSpeechRequest request) async {
    requests.add(request);
    return TtsSpeechResult(spoken: true, text: request.text);
  }
}

final class _FakeFlutterTts extends FlutterTts {
  _FakeFlutterTts(this.voices);

  final List<Map<String, dynamic>> voices;
  final calls = <String>[];

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    calls.add('await:$awaitCompletion');
    return 1;
  }

  @override
  Future<dynamic> get getVoices async => voices;

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    calls.add('voice:${voice['name']}/${voice['locale']}');
    return 1;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('language:$language');
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    calls.add('volume:$volume');
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    calls.add('pitch:$pitch');
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('rate:$rate');
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak:$text');
    return 1;
  }
}
