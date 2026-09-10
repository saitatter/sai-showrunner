import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/heartrate/ble/heart_rate_parser.dart';

void main() {
  test('parses 8-bit BPM only', () {
    final measurement = parseHeartRateMeasurement(Uint8List.fromList([0, 72]));

    expect(measurement.bpm, 72);
    expect(measurement.sensorContactSupported, isFalse);
    expect(measurement.sensorContactDetected, isNull);
    expect(measurement.energyExpended, isNull);
    expect(measurement.rrIntervalsMs, isEmpty);
  });

  test('parses 16-bit BPM', () {
    final measurement = parseHeartRateMeasurement(
      Uint8List.fromList([1, 0x2c, 0x01]),
    );

    expect(measurement.bpm, 300);
  });

  test('parses supported sensor contact states', () {
    expect(
      parseHeartRateMeasurement(
        Uint8List.fromList([2, 80]),
      ).sensorContactDetected,
      isFalse,
    );
    expect(
      parseHeartRateMeasurement(
        Uint8List.fromList([6, 80]),
      ).sensorContactDetected,
      isTrue,
    );
    expect(
      parseHeartRateMeasurement(
        Uint8List.fromList([2, 80]),
      ).sensorContactSupported,
      isTrue,
    );
  });

  test('parses energy expended', () {
    final measurement = parseHeartRateMeasurement(
      Uint8List.fromList([8, 90, 0x34, 0x12]),
    );

    expect(measurement.energyExpended, 0x1234);
  });

  test('parses one and multiple RR intervals in milliseconds', () {
    final one = parseHeartRateMeasurement(
      Uint8List.fromList([16, 100, 0x04, 0x00]),
    );
    final multiple = parseHeartRateMeasurement(
      Uint8List.fromList([16, 100, 0x04, 0x00, 0x08, 0x00]),
    );

    expect(one.rrIntervalsMs, [closeTo(3.90625, 0.00001)]);
    expect(multiple.rrIntervalsMs, [
      closeTo(3.90625, 0.00001),
      closeTo(7.8125, 0.00001),
    ]);
  });

  test('parses all optional fields together', () {
    final measurement = parseHeartRateMeasurement(
      Uint8List.fromList([25, 0x2c, 0x01, 0x34, 0x12, 0x04, 0x00]),
    );

    expect(measurement.bpm, 300);
    expect(measurement.energyExpended, 0x1234);
    expect(measurement.rrIntervalsMs, [closeTo(3.90625, 0.00001)]);
  });

  test('accepts zero and high BPM values', () {
    expect(parseHeartRateMeasurement(Uint8List.fromList([0, 0])).bpm, 0);
    expect(parseHeartRateMeasurement(Uint8List.fromList([0, 255])).bpm, 255);
  });

  test('rejects reserved sensor contact flag', () {
    expect(
      () => parseHeartRateMeasurement(Uint8List.fromList([4, 80])),
      throwsA(isA<HeartRatePacketFormatException>()),
    );
  });

  test('rejects truncated BPM', () {
    expect(
      () => parseHeartRateMeasurement(Uint8List.fromList([1])),
      throwsA(isA<HeartRatePacketFormatException>()),
    );
    expect(
      () => parseHeartRateMeasurement(Uint8List.fromList([0])),
      throwsA(isA<HeartRatePacketFormatException>()),
    );
  });

  test('rejects truncated energy field', () {
    expect(
      () => parseHeartRateMeasurement(Uint8List.fromList([8, 90, 1])),
      throwsA(isA<HeartRatePacketFormatException>()),
    );
  });

  test('rejects an odd trailing RR byte', () {
    expect(
      () => parseHeartRateMeasurement(Uint8List.fromList([16, 90, 1])),
      throwsA(isA<HeartRatePacketFormatException>()),
    );
  });

  test('rejects a zero-length packet', () {
    expect(
      () => parseHeartRateMeasurement(Uint8List(0)),
      throwsA(isA<HeartRatePacketFormatException>()),
    );
  });
}
