import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';
import 'package:showrunner_flutter/plugins/sound/bootstrap.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/plugins/sound/tts_runtime.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configured sound module closes the outputs it creates', () async {
    final root = await Directory.systemTemp.createTemp('sound-module-');
    addTearDown(() => root.delete(recursive: true));
    final registry = DartPluginRegistry();
    final outputs = await registerConfiguredSound(
      registry,
      dataService: ShowRunnerDataService(root),
      ttsService: null,
      soundOutputs: null,
    );
    await registry.initialize();
    await registry.close();
    await expectLater(outputs.playFile(file: 'missing.wav'), throwsStateError);
  });

  test(
    'sound module leaves injected output ownership with its caller',
    () async {
      final outputs = SoundOutputRegistry(defaultOutputId: 'test')
        ..register(CallbackSoundOutput(id: 'test', player: (_) async => true));
      final registry = DartPluginRegistry();
      registerDefaultSound(registry, ttsService: null, soundOutputs: outputs);
      await registry.initialize();
      await registry.close();
      expect(await outputs.playFile(file: 'fixture.wav'), isTrue);
      await outputs.close();
    },
  );

  test(
    'output shutdown aborts anonymous plays and awaits physical cleanup',
    () async {
      final entered = Completer<void>();
      final aborted = Completer<void>();
      final disposed = Completer<void>();
      final outputs = SoundOutputRegistry(defaultOutputId: 'test')
        ..register(
          CallbackSoundOutput(
            id: 'test',
            player: (request) async {
              expect(request.playId, isNotEmpty);
              entered.complete();
              await aborted.future;
              await disposed.future;
              return false;
            },
            aborter: (id) async {
              aborted.complete();
            },
          ),
        );
      final playback = outputs.playFile(file: 'fixture.wav');
      await entered.future;
      var closed = false;
      final closing = outputs.close().then((_) => closed = true);
      await aborted.future;
      expect(closed, isFalse);
      disposed.complete();
      expect(await playback, isFalse);
      await closing;
      await outputs.close();
      await expectLater(
        outputs.playFile(file: 'fixture.wav'),
        throwsStateError,
      );
    },
  );

  test('late output refresh cannot start playback after shutdown', () async {
    final refresh = Completer<void>();
    var plays = 0;
    final outputs =
        SoundOutputRegistry(
          defaultOutputId: 'test',
          refresh: () => refresh.future,
        )..register(
          CallbackSoundOutput(
            id: 'test',
            player: (_) async {
              plays++;
              return true;
            },
          ),
        );
    final pending = expectLater(
      outputs.playFile(file: 'fixture.wav'),
      throwsStateError,
    );
    await outputs.close();
    refresh.complete();
    await pending;
    expect(plays, 0);
  });

  test(
    'speech cancellation physically stops speech and leaves service reusable',
    () async {
      final client = _SpeechClient();
      final service = FlutterTtsSpeechService(client: client);
      final token = DartCancellationToken();
      final pending = expectLater(
        service.speak(TtsSpeechRequest(text: 'test', cancellationToken: token)),
        throwsA(isA<DartCancelledException>()),
      );
      await client.started.future;
      token.cancel();
      await pending;
      expect(client.stops, 1);
      client.hang = false;
      expect(
        (await service.speak(const TtsSpeechRequest(text: 'again'))).spoken,
        isTrue,
      );
      await service.close();
      await service.close();
      expect(client.stops, 2);
      await expectLater(
        service.speak(const TtsSpeechRequest(text: 'late')),
        throwsStateError,
      );
    },
  );

  test(
    'speech shutdown stops pending speech even if platform completion never arrives',
    () async {
      final client = _SpeechClient();
      final service = FlutterTtsSpeechService(client: client);
      final pending = expectLater(
        service.speak(const TtsSpeechRequest(text: 'test')),
        throwsStateError,
      );
      await client.started.future;
      await service.close();
      await pending.timeout(const Duration(seconds: 1));
      expect(client.stops, 1);
    },
  );

  test(
    'file synthesis shutdown waits for its runner and rejects late completion',
    () async {
      final directory = await Directory.systemTemp.createTemp('tts-close-');
      addTearDown(() => directory.delete(recursive: true));
      final entered = Completer<void>();
      final result = Completer<ProcessResult>();
      final service = WindowsTtsFileSynthesisService(
        enabled: true,
        cacheDirectory: directory,
        run: (executable, arguments) {
          entered.complete();
          return result.future;
        },
      );
      final pending = expectLater(
        service.synthesizeToFile(const TtsSpeechRequest(text: 'test')),
        throwsStateError,
      );
      await entered.future;
      var closed = false;
      final closing = service.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      result.complete(ProcessResult(0, 0, '', ''));
      await pending;
      await closing;
      await expectLater(
        service.synthesizeToFile(const TtsSpeechRequest(text: 'late')),
        throwsStateError,
      );
    },
  );
}

final class _SpeechClient extends FlutterTts {
  final started = Completer<void>();
  final never = Completer<dynamic>();
  bool hang = true;
  int stops = 0;
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    if (!started.isCompleted) started.complete();
    return hang ? never.future : Future.value(1);
  }

  @override
  Future<dynamic> stop() async {
    stops++;
    return 1;
  }
}
