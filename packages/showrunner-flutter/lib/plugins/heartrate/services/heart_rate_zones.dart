final class HeartRateZoneConfig {
  const HeartRateZoneConfig({
    required this.id,
    required this.name,
    required this.minBpm,
    this.maxBpm,
    required this.color,
  });

  final String id;
  final String name;
  final int minBpm;
  final int? maxBpm;
  final String color;

  bool contains(int bpm) => bpm >= minBpm && (maxBpm == null || bpm <= maxBpm!);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'minBpm': minBpm,
    'maxBpm': maxBpm,
    'color': color,
  };
}

const defaultHeartRateZones = <HeartRateZoneConfig>[
  HeartRateZoneConfig(
    id: 'zone-1',
    name: 'Zone 1',
    minBpm: 0,
    maxBpm: 99,
    color: '#60a5fa',
  ),
  HeartRateZoneConfig(
    id: 'zone-2',
    name: 'Zone 2',
    minBpm: 100,
    maxBpm: 119,
    color: '#34d399',
  ),
  HeartRateZoneConfig(
    id: 'zone-3',
    name: 'Zone 3',
    minBpm: 120,
    maxBpm: 139,
    color: '#facc15',
  ),
  HeartRateZoneConfig(
    id: 'zone-4',
    name: 'Zone 4',
    minBpm: 140,
    maxBpm: 159,
    color: '#fb923c',
  ),
  HeartRateZoneConfig(
    id: 'zone-5',
    name: 'Zone 5',
    minBpm: 160,
    color: '#f87171',
  ),
];

List<String> validateHeartRateZones(Iterable<HeartRateZoneConfig> zones) {
  final values = zones.toList();
  final errors = <String>[];
  final ids = <String>{};
  for (var index = 0; index < values.length; index++) {
    final zone = values[index];
    if (zone.id.trim().isEmpty) errors.add('Zone ${index + 1} needs an ID.');
    if (!ids.add(zone.id)) errors.add('Zone IDs must be unique.');
    if (zone.name.trim().isEmpty) errors.add('Zone ${index + 1} needs a name.');
    if (zone.minBpm < 0) errors.add('${zone.name}: BPM cannot be negative.');
    if (zone.maxBpm != null && zone.maxBpm! < zone.minBpm) {
      errors.add('${zone.name}: maximum BPM must not be below minimum BPM.');
    }
    if (index > 0 && zone.minBpm < values[index - 1].minBpm) {
      errors.add('Zones must be sorted by minimum BPM.');
    }
    final previous = index == 0 ? null : values[index - 1];
    if (previous?.maxBpm != null && zone.minBpm <= previous!.maxBpm!) {
      errors.add('Heart-rate zones cannot overlap.');
    }
  }
  for (var index = 0; index < values.length - 1; index++) {
    if (values[index].maxBpm == null) {
      errors.add('Only the final heart-rate zone may be open-ended.');
    }
  }
  return List.unmodifiable(errors);
}

HeartRateZoneConfig? heartRateZoneFor(
  int bpm,
  Iterable<HeartRateZoneConfig> zones,
) {
  for (final zone in zones) {
    if (zone.contains(bpm)) return zone;
  }
  return null;
}
