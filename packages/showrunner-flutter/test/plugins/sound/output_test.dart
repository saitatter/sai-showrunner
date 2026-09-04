import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/sound/manifest.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';

void main() {
  test('fans out splitter redirects with mute and scaled volume', () async {
    final output = _RecordingOutput('system.main');
    final registry = SoundOutputRegistry(defaultOutputId: 'splitter');
    registry.register(output);
    registry.registerSplitter('splitter', [
      const AudioSplitterRedirect(output: 'system.main', volume: 50),
      const AudioSplitterRedirect(
        output: 'system.main',
        volume: 100,
        mute: true,
      ),
    ]);

    final played = await registry.playFile(
      file: 'alert.wav',
      startSec: 2,
      endSec: 5,
      volume: 80,
    );

    expect(played, isTrue);
    expect(output.requests, hasLength(1));
    expect(output.requests.single.file, 'alert.wav');
    expect(output.requests.single.startSec, 2);
    expect(output.requests.single.endSec, 5);
    expect(output.requests.single.volume, 40);
  });

  test('nested redirects keep the loudest route to a direct output', () async {
    final output = _RecordingOutput('system.main');
    final registry = SoundOutputRegistry(defaultOutputId: 'root');
    registry.register(output);
    registry.registerSplitter('child', [
      const AudioSplitterRedirect(output: 'system.main', volume: 100),
    ]);
    registry.registerSplitter('root', [
      const AudioSplitterRedirect(output: 'child', volume: 50),
      const AudioSplitterRedirect(output: 'system.main', volume: 30),
    ]);

    final played = await registry.playFile(file: 'voice.wav', volume: 80);

    expect(played, isTrue);
    expect(output.requests, hasLength(1));
    expect(output.requests.single.volume, 40);
  });

  test('splitter cycles terminate and missing outputs are ignored', () async {
    final registry = SoundOutputRegistry(defaultOutputId: 'root');
    registry.registerSplitter('root', [
      const AudioSplitterRedirect(output: 'child'),
      const AudioSplitterRedirect(output: 'missing'),
    ]);
    registry.registerSplitter('child', [
      const AudioSplitterRedirect(output: 'root'),
    ]);

    expect(await registry.playFile(file: 'cycle.wav'), isFalse);
  });

  test('sound action resolves the legacy file and output fields', () async {
    final output = _RecordingOutput('system.main');
    final outputs = SoundOutputRegistry(defaultOutputId: 'system.main')
      ..register(output);
    final registry = DartPluginRegistry()
      ..register(createSoundPlugin(soundOutputs: outputs));

    final result = await registry.invokeAction('sound', 'sound', {
      'sound': 'notification.wav',
      'volume': 65,
      'startTime': 1,
      'endTime': 4,
    });

    expect(result, {'played': true, 'sound': 'notification.wav'});
    expect(output.requests.single.volume, 65);
    expect(output.requests.single.startSec, 1);
    expect(output.requests.single.endSec, 4);
  });
}

final class _RecordingOutput implements SoundOutput {
  _RecordingOutput(this.id);

  @override
  final String id;
  final requests = <SoundPlayRequest>[];

  @override
  Future<bool> playFile(SoundPlayRequest request) async {
    requests.add(request);
    return true;
  }
}
