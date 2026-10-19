import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/heartrate/services/heart_rate_stats.dart';
import 'package:showrunner_flutter/plugins/heartrate/services/heart_rate_zones.dart';

void main() {
  group('heart-rate zones', () {
    test('uses inclusive boundaries and open-ended final zone', () {
      expect(heartRateZoneFor(0, defaultHeartRateZones)?.id, 'zone-1');
      expect(heartRateZoneFor(99, defaultHeartRateZones)?.id, 'zone-1');
      expect(heartRateZoneFor(100, defaultHeartRateZones)?.id, 'zone-2');
      expect(heartRateZoneFor(160, defaultHeartRateZones)?.id, 'zone-5');
      expect(heartRateZoneFor(300, defaultHeartRateZones)?.id, 'zone-5');
    });

    test(
      'rejects overlap, invalid ranges, duplicate IDs, and bad ordering',
      () {
        final zones = [
          const HeartRateZoneConfig(
            id: 'a',
            name: 'A',
            minBpm: 100,
            maxBpm: 150,
            color: '#fff',
          ),
          const HeartRateZoneConfig(
            id: 'a',
            name: 'B',
            minBpm: 90,
            maxBpm: 80,
            color: '#fff',
          ),
          const HeartRateZoneConfig(
            id: 'c',
            name: 'C',
            minBpm: 200,
            color: '#fff',
          ),
        ];

        final errors = validateHeartRateZones(zones);
        expect(errors, contains('Zone IDs must be unique.'));
        expect(
          errors,
          contains('B: maximum BPM must not be below minimum BPM.'),
        );
        expect(errors, contains('Zones must be sorted by minimum BPM.'));
      },
    );

    test('only permits an open-ended zone at the end', () {
      final errors = validateHeartRateZones([
        const HeartRateZoneConfig(id: 'a', name: 'A', minBpm: 0, color: '#fff'),
        const HeartRateZoneConfig(
          id: 'b',
          name: 'B',
          minBpm: 100,
          maxBpm: 120,
          color: '#fff',
        ),
      ]);

      expect(
        errors,
        contains('Only the final heart-rate zone may be open-ended.'),
      );
    });
  });

  test('tracks incremental min, max, average, and reset', () {
    var stats = const HeartRateStats();
    stats = stats.add(72).add(120).add(96);

    expect(stats.sampleCount, 3);
    expect(stats.minBpm, 72);
    expect(stats.maxBpm, 120);
    expect(stats.averageBpm, 96);
    expect(stats.reset().sampleCount, 0);
  });
}
