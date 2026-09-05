import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:media_kit/media_kit.dart';

import 'output.dart';

const _waveHeaderDone = 0x00000001;

final class SoundDeviceInfo {
  const SoundDeviceInfo({required this.id, required this.name});

  final String id;
  final String name;
}

final class PcmWaveInfo {
  const PcmWaveInfo({
    required this.channels,
    required this.sampleRate,
    required this.averageBytesPerSecond,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  final int channels;
  final int sampleRate;
  final int averageBytesPerSecond;
  final int blockAlign;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;
}

PcmWaveInfo parsePcmWave(Uint8List bytes) {
  if (bytes.length < 12 ||
      _fourCc(bytes, 0) != 'RIFF' ||
      _fourCc(bytes, 8) != 'WAVE') {
    throw const FormatException('Sound file is not a RIFF/WAVE file.');
  }

  int? channels;
  int? sampleRate;
  int? averageBytesPerSecond;
  int? blockAlign;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunk = _fourCc(bytes, offset);
    final length = _uint32(bytes, offset + 4);
    final contentOffset = offset + 8;
    final contentEnd = contentOffset + length;
    if (contentEnd > bytes.length) {
      throw const FormatException('WAVE chunk extends beyond the file.');
    }
    if (chunk == 'fmt ' && length >= 16) {
      final format = _uint16(bytes, contentOffset);
      if (format != 1) {
        throw const FormatException('Only PCM WAVE files are supported.');
      }
      channels = _uint16(bytes, contentOffset + 2);
      sampleRate = _uint32(bytes, contentOffset + 4);
      averageBytesPerSecond = _uint32(bytes, contentOffset + 8);
      blockAlign = _uint16(bytes, contentOffset + 12);
      bitsPerSample = _uint16(bytes, contentOffset + 14);
    } else if (chunk == 'data') {
      dataOffset = contentOffset;
      dataLength = length;
    }
    offset = contentEnd + (length.isOdd ? 1 : 0);
  }

  if (channels == null ||
      sampleRate == null ||
      averageBytesPerSecond == null ||
      blockAlign == null ||
      bitsPerSample == null ||
      dataOffset == null ||
      dataLength == null ||
      channels <= 0 ||
      sampleRate <= 0 ||
      averageBytesPerSecond <= 0 ||
      blockAlign <= 0 ||
      dataLength <= 0) {
    throw const FormatException('WAVE file is missing a valid PCM data chunk.');
  }
  return PcmWaveInfo(
    channels: channels,
    sampleRate: sampleRate,
    averageBytesPerSecond: averageBytesPerSecond,
    blockAlign: blockAlign,
    bitsPerSample: bitsPerSample,
    dataOffset: dataOffset,
    dataLength: dataLength,
  );
}

Uint8List trimPcmWave(
  Uint8List bytes,
  PcmWaveInfo info,
  SoundPlayRequest request,
) {
  final startFrame =
      (request.startSec.clamp(0, double.infinity) * info.sampleRate).floor();
  final endFrame = request.endSec.isFinite
      ? (request.endSec.clamp(0, double.infinity) * info.sampleRate).floor()
      : info.dataLength ~/ info.blockAlign;
  final start = (startFrame * info.blockAlign).clamp(0, info.dataLength);
  final end = (endFrame * info.blockAlign).clamp(start, info.dataLength);
  if (end <= start) return Uint8List(0);
  return Uint8List.fromList(
    bytes.sublist(info.dataOffset + start, info.dataOffset + end),
  );
}

List<SoundDeviceInfo> enumerateWindowsSoundOutputs() {
  if (!Platform.isWindows) return const [];
  final bindings = _WaveOutBindings();
  final count = bindings.getNumDevs();
  final devices = <SoundDeviceInfo>[];
  for (var index = 0; index < count; index++) {
    final name = bindings.getDeviceName(index);
    if (name == null || name.isEmpty) continue;
    devices.add(SoundDeviceInfo(id: 'system.winmm.$index', name: name));
  }
  return devices;
}

SoundOutputRegistry createDefaultSoundOutputRegistry({
  String? defaultOutputId,
}) {
  final registry = SoundOutputRegistry(
    defaultOutputId: defaultOutputId?.trim().isNotEmpty == true
        ? defaultOutputId!.trim()
        : 'system.default',
  );
  if (!Platform.isWindows) return registry;

  registry.register(
    MediaKitSoundOutput(id: 'system.default', name: 'Default output'),
  );
  registry.register(
    MediaKitSoundOutput(
      id: 'system.communications',
      name: 'Communications output',
    ),
  );
  for (final device in enumerateWindowsSoundOutputs()) {
    final index = int.tryParse(device.id.split('.').last);
    if (index == null) continue;
    registry.register(
      MediaKitSoundOutput(
        id: device.id,
        name: device.name,
        preferredDeviceDescription: device.name,
      ),
    );
  }
  return registry;
}

typedef MediaKitSoundPlayback =
    Future<void> Function(
      SoundPlayRequest request,
      String? preferredDeviceDescription,
    );

/// Plays local media files for the desktop audio output.
///
/// media_kit uses libmpv on Windows, which keeps codec support broad (mp3,
/// ogg, flac, m4a, wav, etc.) and exposes WASAPI devices instead of relying on
/// the old WinMM PCM-only path. The callback is intentionally injectable so
/// the action layer can be tested without loading native libmpv.
final class MediaKitSoundOutput implements SoundOutput {
  MediaKitSoundOutput({
    required this.id,
    required this.name,
    this.preferredDeviceDescription,
    this.playback,
  });

  @override
  final String id;
  final String name;
  final String? preferredDeviceDescription;
  final MediaKitSoundPlayback? playback;

  @override
  Future<bool> playFile(SoundPlayRequest request) async {
    if (playback != null) {
      await playback!(request, preferredDeviceDescription);
      return true;
    }
    if (!Platform.isWindows) return false;

    final file = File(request.file);
    if (!await file.exists()) return false;
    final start = request.startSec.clamp(0, double.infinity).toDouble();
    final end = request.endSec;
    if (end.isFinite && end <= start) return false;

    final player = Player();
    try {
      final media = Media(
        Uri.file(file.absolute.path).toString(),
        start: Duration(microseconds: (start * 1000000).round()),
        end: end.isFinite
            ? Duration(microseconds: (end * 1000000).round())
            : null,
      );
      await player.open(media, play: false);
      await player.setVolume(request.volume.clamp(0, 100).toDouble());
      final preferred = preferredDeviceDescription?.trim();
      if (preferred != null && preferred.isNotEmpty) {
        final device = await _findAudioDevice(player, preferred);
        if (device == null) {
          throw StateError('Audio output is unavailable: $preferred');
        }
        await player.setAudioDevice(device);
      } else {
        await player.setAudioDevice(AudioDevice.auto());
      }
      await player.play();
      await Future.any<void>([
        player.stream.completed.firstWhere((completed) => completed),
        player.stream.error.first.then<void>(
          (message) => throw StateError('Audio playback failed: $message'),
        ),
      ]);
      return true;
    } finally {
      await player.dispose();
    }
  }
}

Future<AudioDevice?> _findAudioDevice(Player player, String description) async {
  AudioDevice? match(Iterable<AudioDevice> devices) {
    for (final device in devices) {
      if (_matchesAudioDevice(device, description)) return device;
    }
    return null;
  }

  final immediate = match(player.state.audioDevices);
  if (immediate != null) return immediate;
  try {
    return await player.stream.audioDevices
        .map(match)
        .where((device) => device != null)
        .cast<AudioDevice>()
        .first
        .timeout(const Duration(seconds: 3));
  } on Object {
    return null;
  }
}

bool _matchesAudioDevice(AudioDevice device, String description) {
  final target = description.trim().toLowerCase();
  final deviceDescription = device.description.trim().toLowerCase();
  final deviceName = device.name.trim().toLowerCase();
  return deviceDescription == target ||
      deviceDescription.startsWith(target) ||
      deviceName == target ||
      deviceName.endsWith(target);
}

final class WindowsWaveOutSoundOutput implements SoundOutput {
  WindowsWaveOutSoundOutput({
    required this.id,
    required this.name,
    required this.deviceId,
  });

  @override
  final String id;
  final String name;
  final int deviceId;

  @override
  Future<bool> playFile(SoundPlayRequest request) async {
    if (!Platform.isWindows) return false;
    try {
      final bytes = await File(request.file).readAsBytes();
      final info = parsePcmWave(bytes);
      final pcm = trimPcmWave(bytes, info, request);
      if (pcm.isEmpty) return false;
      await _WaveOutBindings().play(
        deviceId: deviceId,
        info: info,
        pcm: pcm,
        volume: request.volume,
      );
      return true;
    } on Object {
      return false;
    }
  }
}

final class _WaveOutBindings {
  _WaveOutBindings() : _library = DynamicLibrary.open('winmm.dll');

  final DynamicLibrary _library;

  int getNumDevs() =>
      _library.lookupFunction<_WaveOutGetNumDevsNative, _WaveOutGetNumDevsDart>(
        'waveOutGetNumDevs',
      )();

  String? getDeviceName(int deviceId) {
    final caps = calloc<Uint8>(84);
    try {
      final result = _library
          .lookupFunction<_WaveOutGetDevCapsNative, _WaveOutGetDevCapsDart>(
            'waveOutGetDevCapsW',
          )(deviceId, caps, 84);
      if (result != 0) return null;
      final chars = <int>[];
      for (var offset = 8; offset + 1 < 72; offset += 2) {
        final value = caps[offset] | (caps[offset + 1] << 8);
        if (value == 0) break;
        chars.add(value);
      }
      return String.fromCharCodes(chars).trim();
    } finally {
      calloc.free(caps);
    }
  }

  Future<void> play({
    required int deviceId,
    required PcmWaveInfo info,
    required Uint8List pcm,
    required double volume,
  }) async {
    final handle = calloc<IntPtr>();
    final format = calloc<_WaveFormatEx>();
    final header = calloc<_WaveHeader>();
    final buffer = calloc<Uint8>(pcm.length);
    var opened = false;
    var prepared = false;
    try {
      buffer.asTypedList(pcm.length).setAll(0, pcm);
      format.ref
        ..formatTag = 1
        ..channels = info.channels
        ..samplesPerSec = info.sampleRate
        ..avgBytesPerSec = info.averageBytesPerSecond
        ..blockAlign = info.blockAlign
        ..bitsPerSample = info.bitsPerSample
        ..size = 0;
      header.ref
        ..data = buffer
        ..bufferLength = pcm.length
        ..bytesRecorded = 0
        ..user = 0
        ..flags = 0
        ..loops = 0
        ..next = nullptr
        ..reserved = 0;

      final open = _library
          .lookupFunction<_WaveOutOpenNative, _WaveOutOpenDart>(
            'waveOutOpen',
          )(handle, deviceId, format, nullptr, 0, 0);
      if (open != 0) throw StateError('waveOutOpen failed ($open).');
      opened = true;

      final setVolume = _library
          .lookupFunction<_WaveOutSetVolumeNative, _WaveOutSetVolumeDart>(
            'waveOutSetVolume',
          );
      final level = (volume.clamp(0, 100) / 100 * 0xFFFF).round();
      setVolume(handle.value, level | (level << 16));

      final prepare = _library
          .lookupFunction<
            _WaveOutPrepareHeaderNative,
            _WaveOutPrepareHeaderDart
          >(
            'waveOutPrepareHeader',
          )(handle.value, header, sizeOf<_WaveHeader>());
      if (prepare != 0) {
        throw StateError('waveOutPrepareHeader failed ($prepare).');
      }
      prepared = true;
      final write = _library
          .lookupFunction<_WaveOutWriteNative, _WaveOutWriteDart>(
            'waveOutWrite',
          )(handle.value, header, sizeOf<_WaveHeader>());
      if (write != 0) throw StateError('waveOutWrite failed ($write).');

      final timeout = DateTime.now().add(
        Duration(
          milliseconds:
              (pcm.length / info.averageBytesPerSecond * 1000).ceil() + 2000,
        ),
      );
      while (header.ref.flags & _waveHeaderDone == 0 &&
          DateTime.now().isBefore(timeout)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      if (opened) {
        _library.lookupFunction<_WaveOutResetNative, _WaveOutResetDart>(
          'waveOutReset',
        )(handle.value);
        if (prepared) {
          _library.lookupFunction<
            _WaveOutUnprepareHeaderNative,
            _WaveOutUnprepareHeaderDart
          >('waveOutUnprepareHeader')(
            handle.value,
            header,
            sizeOf<_WaveHeader>(),
          );
        }
        _library.lookupFunction<_WaveOutCloseNative, _WaveOutCloseDart>(
          'waveOutClose',
        )(handle.value);
      }
      calloc.free(buffer);
      calloc.free(header);
      calloc.free(format);
      calloc.free(handle);
    }
  }
}

final class _WaveFormatEx extends Struct {
  @Uint16()
  external int formatTag;
  @Uint16()
  external int channels;
  @Uint32()
  external int samplesPerSec;
  @Uint32()
  external int avgBytesPerSec;
  @Uint16()
  external int blockAlign;
  @Uint16()
  external int bitsPerSample;
  @Uint16()
  external int size;
}

final class _WaveHeader extends Struct {
  external Pointer<Uint8> data;
  @Uint32()
  external int bufferLength;
  @Uint32()
  external int bytesRecorded;
  @IntPtr()
  external int user;
  @Uint32()
  external int flags;
  @Uint32()
  external int loops;
  external Pointer<_WaveHeader> next;
  @IntPtr()
  external int reserved;
}

typedef _WaveOutGetNumDevsNative = Uint32 Function();
typedef _WaveOutGetNumDevsDart = int Function();
typedef _WaveOutGetDevCapsNative =
    Uint32 Function(Uint32 deviceId, Pointer<Uint8> caps, Uint32 size);
typedef _WaveOutGetDevCapsDart =
    int Function(int deviceId, Pointer<Uint8> caps, int size);
typedef _WaveOutOpenNative =
    Uint32 Function(
      Pointer<IntPtr> handle,
      Uint32 deviceId,
      Pointer<_WaveFormatEx> format,
      Pointer<Void> callback,
      IntPtr instance,
      Uint32 flags,
    );
typedef _WaveOutOpenDart =
    int Function(
      Pointer<IntPtr> handle,
      int deviceId,
      Pointer<_WaveFormatEx> format,
      Pointer<Void> callback,
      int instance,
      int flags,
    );
typedef _WaveOutSetVolumeNative = Uint32 Function(IntPtr handle, Uint32 volume);
typedef _WaveOutSetVolumeDart = int Function(int handle, int volume);
typedef _WaveOutPrepareHeaderNative =
    Uint32 Function(IntPtr handle, Pointer<_WaveHeader> header, Uint32 size);
typedef _WaveOutPrepareHeaderDart =
    int Function(int handle, Pointer<_WaveHeader> header, int size);
typedef _WaveOutWriteNative =
    Uint32 Function(IntPtr handle, Pointer<_WaveHeader> header, Uint32 size);
typedef _WaveOutWriteDart =
    int Function(int handle, Pointer<_WaveHeader> header, int size);
typedef _WaveOutResetNative = Uint32 Function(IntPtr handle);
typedef _WaveOutResetDart = int Function(int handle);
typedef _WaveOutUnprepareHeaderNative =
    Uint32 Function(IntPtr handle, Pointer<_WaveHeader> header, Uint32 size);
typedef _WaveOutUnprepareHeaderDart =
    int Function(int handle, Pointer<_WaveHeader> header, int size);
typedef _WaveOutCloseNative = Uint32 Function(IntPtr handle);
typedef _WaveOutCloseDart = int Function(int handle);

String _fourCc(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));

int _uint16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
