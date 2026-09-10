import 'dart:typed_data';

final class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.bpm,
    required this.sensorContactSupported,
    this.sensorContactDetected,
    this.energyExpended,
    this.rrIntervalsMs = const [],
  });

  final int bpm;
  final bool sensorContactSupported;
  final bool? sensorContactDetected;
  final int? energyExpended;
  final List<double> rrIntervalsMs;
}

final class HeartRatePacketFormatException extends FormatException {
  const HeartRatePacketFormatException(super.message);
}

/// Parses a Bluetooth SIG Heart Rate Measurement characteristic value.
HeartRateMeasurement parseHeartRateMeasurement(Uint8List packet) {
  if (packet.isEmpty) {
    throw const HeartRatePacketFormatException('Heart-rate packet is empty.');
  }

  final flags = packet[0];
  var offset = 1;
  final uses16BitValue = flags & 0x01 != 0;
  final bpm = uses16BitValue
      ? _readUint16(packet, offset, 'heart-rate value')
      : _readUint8(packet, offset, 'heart-rate value');
  offset += uses16BitValue ? 2 : 1;

  final sensorContactBits = (flags >> 1) & 0x03;
  if (sensorContactBits == 2) {
    throw const HeartRatePacketFormatException(
      'Heart-rate packet uses a reserved sensor-contact value.',
    );
  }
  final sensorContactSupported = sensorContactBits != 0;
  final sensorContactDetected = sensorContactBits == 0
      ? null
      : sensorContactBits == 3;

  int? energyExpended;
  if (flags & 0x08 != 0) {
    energyExpended = _readUint16(packet, offset, 'energy expended');
    offset += 2;
  }

  final rrIntervalsMs = <double>[];
  if (flags & 0x10 != 0) {
    final remaining = packet.length - offset;
    if (remaining.isOdd) {
      throw const HeartRatePacketFormatException(
        'Heart-rate packet has an incomplete RR interval.',
      );
    }
    while (offset < packet.length) {
      final raw = _readUint16(packet, offset, 'RR interval');
      rrIntervalsMs.add(raw * 1000 / 1024);
      offset += 2;
    }
  }

  return HeartRateMeasurement(
    bpm: bpm,
    sensorContactSupported: sensorContactSupported,
    sensorContactDetected: sensorContactDetected,
    energyExpended: energyExpended,
    rrIntervalsMs: List.unmodifiable(rrIntervalsMs),
  );
}

int _readUint16(Uint8List packet, int offset, String field) {
  if (offset + 1 >= packet.length) {
    throw HeartRatePacketFormatException(
      'Heart-rate packet is truncated while reading $field.',
    );
  }
  return packet[offset] | (packet[offset + 1] << 8);
}

int _readUint8(Uint8List packet, int offset, String field) {
  if (offset >= packet.length) {
    throw HeartRatePacketFormatException(
      'Heart-rate packet is truncated while reading $field.',
    );
  }
  return packet[offset];
}
