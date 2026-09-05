import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/sound/manifest.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';
import 'package:showrunner_flutter/plugins/sound/windows_audio.dart';

void main() {
  test('parses PCM WAVE data and trims playback to frame boundaries', () {
    final bytes = _waveBytes([10, 20, 30, 40], sampleRate: 1000);
    final info = parsePcmWave(bytes);

    expect(info.channels, 1);
    expect(info.sampleRate, 1000);
    expect(info.bitsPerSample, 8);
    expect(
      trimPcmWave(
        bytes,
        info,
        const SoundPlayRequest(file: 'test.wav', startSec: .001, endSec: .003),
      ),
      [20, 30],
    );
  });

  test('rejects non-PCM WAVE formats', () {
    final bytes = _waveBytes([10, 20], sampleRate: 1000);
    bytes[20] = 3;
    expect(() => parsePcmWave(bytes), throwsFormatException);
  });

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

  test('applies the configured global volume to sound actions', () async {
    final output = _RecordingOutput('system.main');
    final outputs = SoundOutputRegistry(defaultOutputId: 'system.main')
      ..register(output);
    final registry = DartPluginRegistry()
      ..register(createSoundPlugin(soundOutputs: outputs, globalVolume: 40));

    await registry.invokeAction('sound', 'sound', {
      'sound': 'notification.wav',
      'volume': 75,
    });

    expect(output.requests.single.volume, 30);
  });

  test('exposes legacy global volume and default output settings', () {
    final plugin = createSoundPlugin();

    expect(plugin.settings.map((setting) => setting.id), [
      'globalVolume',
      'defaultOutput',
    ]);
    expect(plugin.settings.first.defaultValue, 100);
    expect(plugin.settings.last.defaultValue, 'system.default');
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

Uint8List _waveBytes(List<int> samples, {required int sampleRate}) {
  final bytes = Uint8List(44 + samples.length);
  final view = ByteData.sublistView(bytes);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  void uint16(int offset, int value) =>
      view.setUint16(offset, value, Endian.little);
  void uint32(int offset, int value) =>
      view.setUint32(offset, value, Endian.little);

  ascii(0, 'RIFF');
  uint32(4, bytes.length - 8);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  uint32(16, 16);
  uint16(20, 1);
  uint16(22, 1);
  uint32(24, sampleRate);
  uint32(28, sampleRate);
  uint16(32, 1);
  uint16(34, 8);
  ascii(36, 'data');
  uint32(40, samples.length);
  bytes.setRange(44, bytes.length, samples);
  return bytes;
}
