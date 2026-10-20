import 'dart:async';

typedef SoundOutputResolver = SoundOutput? Function(String id);
typedef SoundFilePlayer = Future<bool> Function(SoundPlayRequest request);
typedef SoundFileAborter = Future<void> Function(String playId);
typedef SoundOutputRefresher = Future<void> Function();

final class SoundPlayRequest {
  const SoundPlayRequest({
    required this.file,
    this.startSec = 0,
    this.endSec = double.infinity,
    this.volume = 100,
    this.playId,
  });

  final String file;
  final double startSec;
  final double endSec;
  final double volume;
  final String? playId;

  SoundPlayRequest withVolume(double nextVolume) => SoundPlayRequest(
    file: file,
    startSec: startSec,
    endSec: endSec,
    volume: nextVolume,
    playId: playId,
  );
}

abstract interface class SoundOutput {
  String get id;

  Future<bool> playFile(SoundPlayRequest request);
}

abstract interface class AbortableSoundOutput implements SoundOutput {
  Future<void> abortPlay(String playId);
}

final class CallbackSoundOutput implements AbortableSoundOutput {
  CallbackSoundOutput({required this.id, required this.player, this.aborter});

  @override
  final String id;
  final SoundFilePlayer player;
  final SoundFileAborter? aborter;

  @override
  Future<bool> playFile(SoundPlayRequest request) => player(request);

  @override
  Future<void> abortPlay(String playId) async {
    await aborter?.call(playId);
  }
}

final class AudioSplitterRedirect {
  const AudioSplitterRedirect({
    required this.output,
    this.mute = false,
    this.volume = 100,
  });

  final String? output;
  final bool mute;
  final double volume;

  factory AudioSplitterRedirect.fromJson(Object? value) {
    final config = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final output = config['output']?.toString().trim();
    final rawVolume = config['volume'];
    final volume = rawVolume is num
        ? rawVolume.toDouble()
        : double.tryParse('$rawVolume') ?? 100;
    return AudioSplitterRedirect(
      output: output == null || output.isEmpty ? null : output,
      mute: config['mute'] == true,
      volume: volume.clamp(0, 100).toDouble(),
    );
  }
}

final class AudioSplitterOutput implements AbortableSoundOutput {
  AudioSplitterOutput({
    required this.id,
    required this.redirects,
    required this.resolve,
  });

  @override
  final String id;
  final List<AudioSplitterRedirect> redirects;
  final SoundOutputResolver resolve;
  final Map<String, List<AbortableSoundOutput>> _activePlaybacks = {};

  @override
  Future<bool> playFile(SoundPlayRequest request) async {
    final targets = _resolveTargets(request.volume);
    if (targets.isEmpty) return false;

    final playId = request.playId;
    final abortableTargets = targets
        .map((target) => target.output)
        .whereType<AbortableSoundOutput>()
        .toList(growable: false);
    if (playId != null && abortableTargets.isNotEmpty) {
      _activePlaybacks[playId] = abortableTargets;
    }

    try {
      final results = await Future.wait(
        targets.map((target) async {
          try {
            return await target.output.playFile(
              request.withVolume(target.volume),
            );
          } catch (_) {
            return false;
          }
        }),
      );
      return results.any((result) => result);
    } finally {
      if (playId != null) _activePlaybacks.remove(playId);
    }
  }

  @override
  Future<void> abortPlay(String playId) async {
    final targets = _activePlaybacks[playId];
    if (targets == null) return;
    await Future.wait(targets.map((target) => target.abortPlay(playId)));
  }

  List<_ResolvedSoundOutput> _resolveTargets(double rootVolume) {
    final outputs = <String, _ResolvedSoundOutput>{};
    final processedSplitters = <String>{};
    final stack = <_PendingSoundOutput>[
      _PendingSoundOutput(output: this, volume: rootVolume),
    ];

    while (stack.isNotEmpty) {
      final pending = stack.removeLast();
      if (pending.volume <= 0) continue;

      final output = pending.output;
      if (output is AudioSplitterOutput) {
        if (!processedSplitters.add(output.id)) continue;
        for (final redirect in output.redirects) {
          if (redirect.mute || redirect.output == null) continue;
          final target = resolve(redirect.output!);
          if (target == null) continue;
          stack.add(
            _PendingSoundOutput(
              output: target,
              volume: pending.volume / 100 * redirect.volume,
            ),
          );
        }
        continue;
      }

      final existing = outputs[output.id];
      if (existing == null || pending.volume > existing.volume) {
        outputs[output.id] = _ResolvedSoundOutput(
          output: output,
          volume: pending.volume,
        );
      }
    }

    return outputs.values.toList();
  }
}

final class SoundOutputRegistry {
  SoundOutputRegistry({this.defaultOutputId = 'system.default', this.refresh});

  bool _closed = false;
  Future<void>? _closing;
  int _playSequence = 0;
  final Set<Future<bool>> _pendingPlayback = {};

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = _close();
  }

  Future<void> _close() async {
    try {
      await Future.wait([
        for (final entry in _activePlaybacks.entries.toList())
          if (entry.value is AbortableSoundOutput)
            (entry.value as AbortableSoundOutput).abortPlay(entry.key),
      ]);
    } finally {
      await Future.wait(
        _pendingPlayback.toList().map(
          (pending) =>
              pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        ),
      );
      _pendingAborts.clear();
    }
  }

  String? defaultOutputId;
  final SoundOutputRefresher? refresh;
  final Map<String, SoundOutput> _outputs = {};
  final Map<String, SoundOutput> _activePlaybacks = {};
  final Set<String> _pendingAborts = {};

  Iterable<SoundOutput> get outputs => _outputs.values;

  SoundOutput? find(String id) => _outputs[id];

  void register(SoundOutput output) {
    if (_closed) throw StateError('Sound output registry is closed.');
    if (output.id.trim().isEmpty) {
      throw ArgumentError.value(output.id, 'output.id');
    }
    _outputs[output.id] = output;
  }

  void registerSplitter(String id, Iterable<AudioSplitterRedirect> redirects) {
    register(
      AudioSplitterOutput(
        id: id,
        redirects: List.unmodifiable(redirects),
        resolve: find,
      ),
    );
  }

  void registerSplitterConfig(String id, Object? config) {
    final redirects = config is Map && config['redirects'] is List
        ? (config['redirects'] as List)
              .map(AudioSplitterRedirect.fromJson)
              .toList()
        : const <AudioSplitterRedirect>[];
    registerSplitter(id, redirects);
  }

  Future<bool> playFile({
    String? outputId,
    required String file,
    double startSec = 0,
    double endSec = double.infinity,
    double volume = 100,
    String? playId,
  }) async {
    if (_closed) throw StateError('Sound output registry is closed.');
    // Resource editors persist splitter changes independently of the runtime
    // registry. Refresh persisted outputs before resolving the root so an
    // edited graph takes effect without restarting ShowRunner.
    try {
      await refresh?.call();
    } on Object {
      // Keep cached outputs usable while the resource directory is unavailable.
    }
    if (_closed) throw StateError('Sound output registry is closed.');
    final id = outputId?.trim().isNotEmpty == true
        ? outputId!.trim()
        : defaultOutputId;
    final output = id == null ? null : find(id);
    if (output == null) {
      if (playId != null) _pendingAborts.remove(playId.trim());
      return false;
    }
    final request = SoundPlayRequest(
      file: file,
      startSec: startSec,
      endSec: endSec,
      volume: volume.clamp(0, 100).toDouble(),
      playId: playId?.trim().isNotEmpty == true
          ? playId!.trim()
          : 'sound-owned-${_playSequence++}',
    );
    if (request.playId != null && _pendingAborts.remove(request.playId)) {
      return false;
    }
    if (_activePlaybacks.containsKey(request.playId)) {
      throw StateError('Sound playback ID is already active.');
    }
    if (request.playId != null) _activePlaybacks[request.playId!] = output;
    Future<bool>? pending;
    try {
      pending = output.playFile(request);
      _pendingPlayback.add(pending);
      return await pending;
    } finally {
      _pendingPlayback.remove(pending);
      if (request.playId != null &&
          identical(_activePlaybacks[request.playId], output)) {
        _activePlaybacks.remove(request.playId);
      }
    }
  }

  Future<void> abortPlay(String playId) async {
    final normalized = playId.trim();
    if (normalized.isEmpty) return;
    final output = _activePlaybacks[normalized];
    if (output == null) {
      _pendingAborts.add(normalized);
      return;
    }
    if (output is AbortableSoundOutput) {
      await output.abortPlay(normalized);
    }
  }
}

final class _PendingSoundOutput {
  const _PendingSoundOutput({required this.output, required this.volume});

  final SoundOutput output;
  final double volume;
}

final class _ResolvedSoundOutput {
  const _ResolvedSoundOutput({required this.output, required this.volume});

  final SoundOutput output;
  final double volume;
}
