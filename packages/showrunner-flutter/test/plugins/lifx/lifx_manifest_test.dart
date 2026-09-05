import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/lifx/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test('maps LIFX light changes through the transport', () async {
    final calls = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        createLifxPlugin(
          CallbackLifxTransport(
            getStateCallback: () async => {'on': false},
            setPowerCallback: (on, transition) async {
              calls.add('power:$on:$transition');
              return {'sent': true};
            },
            setColorCallback: (color, transition) async {
              calls.add('color:${color.kelvin}:$transition');
              return {'sent': true};
            },
          ),
        ),
      );

    final result = await registry.invokeAction('lifx', 'setLightState', {
      'state': 'on',
      'color': 'kb(4000, 60)',
      'transition': 1.25,
    });

    expect(calls, ['color:4000.0:0', 'power:true:1250']);
    expect(result, {'updated': true, 'on': true, 'color': 'kb(4000, 60)'});
  });

  test('encodes and parses LIFX LAN v2 packets', () {
    final packet = buildLifxPacket(
      messageType: 107,
      target: parseLifxTarget('d073d50011223344'),
      sequence: 7,
    );
    final data = ByteData.sublistView(packet);

    expect(packet.length, 36);
    expect(data.getUint16(0, Endian.little), 36);
    expect(data.getUint16(2, Endian.little), 1024);
    expect(parseLifxMessageType(packet), 107);
    expect(packet[8], 0xd0);
    expect(packet[23], 7);
  });

  test('parses a LIFX LightState response', () {
    final packet = buildLifxPacket(
      messageType: 107,
      payload: List.filled(52, 0),
    );
    final data = ByteData.sublistView(packet);
    data.setUint16(36, 0, Endian.little);
    data.setUint16(38, 0, Endian.little);
    data.setUint16(40, 32768, Endian.little);
    data.setUint16(42, 4000, Endian.little);
    data.setUint16(86, 65535, Endian.little);

    expect(parseLifxLightState(packet), {
      'on': true,
      'color': 'kb(4000, 50)',
      'hue': 0.0,
      'saturation': 0.0,
      'brightness': closeTo(50, 0.01),
      'kelvin': 4000,
    });
  });

  test('routes resource actions through the configured device host', () async {
    var resolved = false;
    final registry = DartPluginRegistry()
      ..register(
        createLifxPlugin(
          CallbackLifxTransport(
            getStateCallback: () async => {'on': false},
            setPowerCallback: (on, transition) async =>
                throw StateError('base transport'),
            setColorCallback: (color, transition) async =>
                throw StateError('base transport'),
          ),
          transportResolver: (config) {
            expect(config['host'], 'lifx.local');
            expect(config['port'], 56701);
            expect(config['target'], 'd073d50011223344');
            resolved = true;
            return CallbackLifxTransport(
              getStateCallback: () async => {'on': false},
              setPowerCallback: (on, transition) async => {'sent': true},
              setColorCallback: (color, transition) async => {'sent': true},
            );
          },
        ),
      );

    await registry.invokeAction('lifx', 'setPower', {
      'host': 'lifx.local',
      'port': 56701,
      'target': 'd073d50011223344',
      'state': 'on',
    });

    expect(resolved, isTrue);
  });
}
