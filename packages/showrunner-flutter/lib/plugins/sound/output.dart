typedef SoundOutputResolver = SoundOutput? Function(String id);
typedef SoundFilePlayer = Future<bool> Function(SoundPlayRequest request);
typedef SoundOutputRefresher = Future<void> Function();

final class SoundPlayRequest {
  const SoundPlayRequest({
    required this.file,
    this.startSec = 0,
    this.endSec = double.infinity,
    this.volume = 100,
  });

  final String file;
  final double startSec;
  final double endSec;
  final double volume;

  SoundPlayRequest withVolume(double nextVolume) => SoundPlayRequest(
    file: file,
    startSec: startSec,
    endSec: endSec,
    volume: nextVolume,
  );
}

abstract interface class SoundOutput {
  String get id;

  Future<bool> playFile(SoundPlayRequest request);
}

final class CallbackSoundOutput implements SoundOutput {
  CallbackSoundOutput({required this.id, required this.player});

  @override
  final String id;
  final SoundFilePlayer player;

  @override
  Future<bool> playFile(SoundPlayRequest request) => player(request);
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

final class AudioSplitterOutput implements SoundOutput {
  AudioSplitterOutput({
    required this.id,
    required this.redirects,
    required this.resolve,
  });

  @override
  final String id;
  final List<AudioSplitterRedirect> redirects;
  final SoundOutputResolver resolve;

  @override
  Future<bool> playFile(SoundPlayRequest request) async {
    final targets = _resolveTargets(request.volume);
    if (targets.isEmpty) return false;

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

  String? defaultOutputId;
  final SoundOutputRefresher? refresh;
  final Map<String, SoundOutput> _outputs = {};

  Iterable<SoundOutput> get outputs => _outputs.values;

  SoundOutput? find(String id) => _outputs[id];

  void register(SoundOutput output) {
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
  }) async {
    // Resource editors persist splitter changes independently of the runtime
    // registry. Refresh persisted outputs before resolving the root so an
    // edited graph takes effect without restarting ShowRunner.
    try {
      await refresh?.call();
    } on Object {
      // Keep cached outputs usable while the resource directory is unavailable.
    }
    final id = outputId?.trim().isNotEmpty == true
        ? outputId!.trim()
        : defaultOutputId;
    final output = id == null ? null : find(id);
    if (output == null) return Future.value(false);
    return output.playFile(
      SoundPlayRequest(
        file: file,
        startSec: startSec,
        endSec: endSec,
        volume: volume.clamp(0, 100).toDouble(),
      ),
    );
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
