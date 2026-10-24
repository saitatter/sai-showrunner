import 'dart:async';
import '../sound/output.dart';

/// Owns overlay-scoped playback cancellation, deadlines and sound callbacks.
final class OverlayAudioBridge {
  OverlayAudioBridge({
    required this.send,
    this.soundOutputs,
    required this.resolveMedia,
  });
  final Future<bool> Function(String overlayId, String name, List<dynamic> args)
  send;
  final Future<String?> Function(String source, String overlayId) resolveMedia;
  final SoundOutputRegistry? soundOutputs;
  final _active = <(String, String), _Playback>{};
  final _pending = <Future<bool>>{};
  final _registered = <String>{};
  var _sequence = 0;
  var _closed = false;
  Future<void>? _closing;

  Future<bool> playAudio(String overlayId, SoundPlayRequest request) {
    if (_closed || _pending.length >= 64) return Future.value(false);
    final work = _play(overlayId, request);
    _pending.add(work);
    work.then<void>(
      (_) {
        _pending.remove(work);
      },
      onError: (Object _, StackTrace _) {
        _pending.remove(work);
      },
    );
    return work;
  }

  Future<bool> _play(String overlayId, SoundPlayRequest request) async {
    if (overlayId.isEmpty ||
        !request.startSec.isFinite ||
        request.startSec < 0 ||
        (!request.endSec.isFinite && request.endSec != double.infinity) ||
        request.endSec < request.startSec ||
        !request.volume.isFinite ||
        request.volume < 0 ||
        request.volume > 100) {
      return false;
    }
    final duration = request.endSec.isFinite
        ? request.endSec - request.startSec
        : 0.0;
    if (duration > const Duration(days: 1).inSeconds) return false;
    final playId = request.playId?.trim().isNotEmpty == true
        ? request.playId!.trim()
        : 'overlay-audio-${_sequence++}';
    final key = (overlayId, playId);
    if (_active.containsKey(key)) return false;
    final playback = _Playback();
    _active[key] = playback;
    try {
      final media = await resolveMedia(request.file, overlayId);
      if (_closed || playback.done.isCompleted || media == null) return false;
      final delivered = await _send(overlayId, 'overlays_playAudio', [
        media,
        playId,
        request.startSec,
        request.endSec.isFinite ? request.endSec : null,
        request.volume,
      ]);
      if (!delivered || _closed) return false;
      if (duration > 0 && !playback.done.isCompleted) {
        playback.timer = Timer(
          Duration(milliseconds: (duration * 1000).round()),
          playback.finish,
        );
        await playback.done.future;
      }
      return !_closed;
    } on Object {
      return false;
    } finally {
      playback.finish();
      if (identical(_active[key], playback)) _active.remove(key);
    }
  }

  Future<void> cancelAudio(String overlayId, String playId) async {
    _active[(overlayId, playId)]?.finish();
    if (!_closed) await _send(overlayId, 'overlays_cancelAudio', [playId]);
  }

  Future<bool> _send(String overlayId, String name, List<dynamic> args) async {
    try {
      return await send(overlayId, name, args);
    } on Object {
      return false;
    }
  }

  void registerAudioOutput(String overlayId) {
    final outputs = soundOutputs;
    if (_closed || outputs == null || !_registered.add(overlayId)) return;
    outputs.register(
      CallbackSoundOutput(
        id: 'overlay-audio.$overlayId',
        player: (request) => playAudio(overlayId, request),
        aborter: (playId) => cancelAudio(overlayId, playId),
      ),
    );
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final playback in _active.values) {
      playback.finish();
    }
    await Future.wait(_pending.toList());
    _active.clear();
    _registered.clear();
  }
}

final class _Playback {
  final done = Completer<void>();
  Timer? timer;
  void finish() {
    timer?.cancel();
    timer = null;
    if (!done.isCompleted) done.complete();
  }
}
