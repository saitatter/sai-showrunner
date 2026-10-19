final class HeartRateStats {
  const HeartRateStats({
    this.sampleCount = 0,
    this.sumBpm = 0,
    this.minBpm,
    this.maxBpm,
  });

  final int sampleCount;
  final int sumBpm;
  final int? minBpm;
  final int? maxBpm;

  double? get averageBpm => sampleCount == 0 ? null : sumBpm / sampleCount;

  HeartRateStats add(int bpm) => HeartRateStats(
    sampleCount: sampleCount + 1,
    sumBpm: sumBpm + bpm,
    minBpm: minBpm == null ? bpm : (bpm < minBpm! ? bpm : minBpm),
    maxBpm: maxBpm == null ? bpm : (bpm > maxBpm! ? bpm : maxBpm),
  );

  HeartRateStats reset() => const HeartRateStats();

  Map<String, dynamic> toJson() => {
    'sampleCount': sampleCount,
    'min': minBpm,
    'max': maxBpm,
    'avg': averageBpm,
  };
}
