import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_protocol.generated.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              '../../test/fixtures/overlay-protocol.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final resourceId = fixture['resourceId'] as String;
  for (final (index, value) in (fixture['valid'] as List).indexed) {
    test('round trips shared valid envelope $index', () {
      expect(decodeOverlayWire(value['wire'], resourceId), value['logical']);
      expect(
        encodeOverlayWire(value['logical'] as Map<String, dynamic>, resourceId),
        value['wire'],
      );
    });
  }
  for (final (index, value) in (fixture['invalid'] as List).indexed) {
    test('rejects shared invalid envelope $index', () {
      expect(() => decodeOverlayWire(value, resourceId), throwsFormatException);
    });
  }
}
