import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_registry.dart';

abstract interface class LifxTransport {
  Future<RuntimeMap> getState();

  Future<RuntimeMap> setPower(bool on, int transitionMilliseconds);

  Future<RuntimeMap> setColor(
    LightColorValue color,
    int transitionMilliseconds,
  );

  Future<void> close();
}

final class CallbackLifxTransport implements LifxTransport {
  const CallbackLifxTransport({
    required this.getStateCallback,
    required this.setPowerCallback,
    required this.setColorCallback,
    this.closeCallback,
  });

  final Future<RuntimeMap> Function() getStateCallback;
  final Future<RuntimeMap> Function(bool on, int transitionMilliseconds)
  setPowerCallback;
  final Future<RuntimeMap> Function(
    LightColorValue color,
    int transitionMilliseconds,
  )
  setColorCallback;
  final Future<void> Function()? closeCallback;

  @override
  Future<RuntimeMap> getState() => getStateCallback();

  @override
  Future<RuntimeMap> setPower(bool on, int transitionMilliseconds) =>
      setPowerCallback(on, transitionMilliseconds);

  @override
  Future<RuntimeMap> setColor(
    LightColorValue color,
    int transitionMilliseconds,
  ) => setColorCallback(color, transitionMilliseconds);

  @override
  Future<void> close() async => closeCallback?.call();
}

final class LifxUdpTransport implements LifxTransport {
  LifxUdpTransport({
    required this.host,
    this.port = 56700,
    this.target = const <int>[],
  });

  final String host;
  final int port;
  final List<int> target;
  int _sequence = 0;

  @override
  Future<RuntimeMap> getState() async {
    final response = await _request(messageType: 101, responseType: 107);
    return parseLifxLightState(response);
  }

  @override
  Future<RuntimeMap> setPower(bool on, int transitionMilliseconds) => _send(
    messageType: 21,
    payload: _powerPayload(on, transitionMilliseconds),
  );

  @override
  Future<RuntimeMap> setColor(
    LightColorValue color,
    int transitionMilliseconds,
  ) => _send(
    messageType: 102,
    payload: _colorPayload(color, transitionMilliseconds),
  );

  @override
  Future<void> close() async {}

  Future<Uint8List> _request({
    required int messageType,
    required int responseType,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final completer = Completer<Uint8List>();
    late StreamSubscription<RawSocketEvent> subscription;
    void finishError(Object error, [StackTrace? stack]) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }

    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final packet = datagram!.data;
        if (parseLifxMessageType(packet) == responseType &&
            !completer.isCompleted) {
          completer.complete(Uint8List.fromList(packet));
        }
      }
    }, onError: finishError);
    try {
      socket.send(
        buildLifxPacket(
          messageType: messageType,
          target: target,
          sequence: _sequence++ & 0xff,
        ),
        InternetAddress(host),
        port,
      );
      return await completer.future.timeout(const Duration(seconds: 2));
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  Future<RuntimeMap> _send({
    required int messageType,
    List<int> payload = const [],
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.send(
        buildLifxPacket(
          messageType: messageType,
          target: target,
          payload: payload,
          sequence: _sequence++ & 0xff,
        ),
        InternetAddress(host),
        port,
      );
      return {'sent': true, 'messageType': messageType};
    } finally {
      socket.close();
    }
  }
}

Uint8List buildLifxPacket({
  required int messageType,
  List<int> target = const [],
  List<int> payload = const [],
  int sequence = 0,
}) {
  final packet = Uint8List(36 + payload.length);
  final data = ByteData.sublistView(packet);
  data.setUint16(0, packet.length, Endian.little);
  data.setUint16(2, 1024, Endian.little);
  data.setUint32(4, 0, Endian.little);
  packet.setRange(8, 16, _eightBytes(target));
  packet[22] = 0;
  packet[23] = sequence & 0xff;
  data.setUint16(32, messageType, Endian.little);
  packet.setRange(36, packet.length, payload);
  return packet;
}

int parseLifxMessageType(List<int> packet) {
  if (packet.length < 36) return -1;
  return ByteData.sublistView(
    Uint8List.fromList(packet),
  ).getUint16(32, Endian.little);
}

RuntimeMap parseLifxLightState(List<int> packet) {
  if (packet.length < 88 || parseLifxMessageType(packet) != 107) {
    throw const FormatException('Invalid LIFX LightState packet.');
  }
  final data = ByteData.sublistView(Uint8List.fromList(packet));
  final hue = data.getUint16(36, Endian.little) / 65535 * 360;
  final saturation = data.getUint16(38, Endian.little) / 65535 * 100;
  final brightness = data.getUint16(40, Endian.little) / 65535 * 100;
  final kelvin = data.getUint16(42, Endian.little);
  final power = data.getUint16(86, Endian.little);
  return {
    'on': power > 0,
    'color': saturation <= 0.01
        ? 'kb(${kelvin.round()}, ${brightness.round()})'
        : 'hsb(${hue.round()}, ${saturation.round()}, ${brightness.round()})',
    'hue': hue,
    'saturation': saturation,
    'brightness': brightness,
    'kelvin': kelvin,
  };
}

List<int> _powerPayload(bool on, int transitionMilliseconds) {
  final payload = Uint8List(6);
  final data = ByteData.sublistView(payload);
  data.setUint16(0, on ? 65535 : 0, Endian.little);
  data.setUint32(2, transitionMilliseconds.clamp(0, 4294967295), Endian.little);
  return payload;
}

List<int> _colorPayload(LightColorValue color, int transitionMilliseconds) {
  final payload = Uint8List(13);
  final data = ByteData.sublistView(payload);
  data.setUint16(2, _normalized(color.hue ?? 0, 360), Endian.little);
  data.setUint16(4, _normalized(color.saturation ?? 0, 100), Endian.little);
  data.setUint16(6, _normalized(color.brightness, 100), Endian.little);
  data.setUint16(8, color.kelvin?.round() ?? 3500, Endian.little);
  data.setUint32(9, transitionMilliseconds.clamp(0, 4294967295), Endian.little);
  return payload;
}

int _normalized(double value, double maximum) =>
    (value.clamp(0, maximum) / maximum * 65535).round();

List<int> parseLifxTarget(String? value) {
  final text = value?.replaceAll(RegExp(r'[^0-9a-fA-F]'), '') ?? '';
  if (text.isEmpty) return const [];
  if (text.length != 16) {
    throw const FormatException('LIFX target must be 8 bytes of hex.');
  }
  return [
    for (var index = 0; index < text.length; index += 2)
      int.parse(text.substring(index, index + 2), radix: 16),
  ];
}

List<int> _eightBytes(List<int> bytes) => [
  ...bytes.take(8),
  ...List<int>.filled(8 - bytes.length.clamp(0, 8).toInt(), 0),
];

const _lightSchema = DartDataInputSchema(
  label: 'LIFX light state',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Power',
      key: 'state',
      kind: DartDataInputKind.enumeration,
      options: ['on', 'off', 'toggle'],
      defaultValue: 'on',
    ),
    DartDataInputSchema(
      label: 'Device IP / Host',
      key: 'host',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'LAN Port',
      key: 'port',
      kind: DartDataInputKind.number,
      defaultValue: 56700,
    ),
    DartDataInputSchema(
      label: 'Target MAC (hex, optional)',
      key: 'target',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Color',
      key: 'color',
      kind: DartDataInputKind.lightColor,
    ),
    DartDataInputSchema(
      label: 'Transition (seconds)',
      key: 'transition',
      kind: DartDataInputKind.number,
      defaultValue: 0.5,
    ),
  ],
);

typedef LifxTransportResolver = LifxTransport Function(RuntimeMap config);

DartPluginManifest createLifxPlugin(
  LifxTransport transport, {
  LifxTransportResolver? transportResolver,
}) => DartPluginManifest(
  id: 'lifx',
  name: 'LIFX',
  settings: const [
    DartSettingDefinition(id: 'host', displayName: 'Device IP / Host'),
    DartSettingDefinition(
      id: 'port',
      displayName: 'LAN Port',
      defaultValue: 56700,
    ),
    DartSettingDefinition(
      id: 'target',
      displayName: 'Target MAC (hex, optional)',
    ),
    DartSettingDefinition(
      id: 'subnetMask',
      displayName: 'Discovery Subnet Mask',
      defaultValue: '255.255.255.255',
    ),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'lifx',
      actionId: 'getState',
      displayName: 'Get Light State',
      invoke: (config, context) =>
          (transportResolver?.call(config) ?? transport).getState(),
    ),
    DartActionDefinition(
      pluginId: 'lifx',
      actionId: 'setPower',
      displayName: 'Set Power',
      configSchema: _lightSchema,
      invoke: (config, context) =>
          _setPower(transportResolver?.call(config) ?? transport, config),
    ),
    DartActionDefinition(
      pluginId: 'lifx',
      actionId: 'setColor',
      displayName: 'Set Color',
      configSchema: _lightSchema,
      invoke: (config, context) =>
          _setColor(transportResolver?.call(config) ?? transport, config),
    ),
    DartActionDefinition(
      pluginId: 'lifx',
      actionId: 'setLightState',
      displayName: 'Set Light State',
      configSchema: _lightSchema,
      invoke: (config, context) =>
          _setLightState(transportResolver?.call(config) ?? transport, config),
    ),
  ],
);

Future<Object?> _setPower(LifxTransport transport, RuntimeMap config) async {
  var state = config['state'] ?? 'on';
  if (state == 'toggle') {
    final current = await transport.getState();
    state = current['on'] != true;
  }
  return transport.setPower(
    state == true || state == 'on',
    _transition(config),
  );
}

Future<Object?> _setColor(LifxTransport transport, RuntimeMap config) async {
  final color = parseLightColor(config['color']?.toString());
  if (color == null) throw ArgumentError('A valid LIFX color is required.');
  return transport.setColor(color, _transition(config));
}

Future<Object?> _setLightState(
  LifxTransport transport,
  RuntimeMap config,
) async {
  final current = await transport.getState();
  var state = config['state'] ?? 'on';
  if (state == 'toggle') state = current['on'] != true;
  final on = state == true || state == 'on';
  final color = parseLightColor(config['color']?.toString());
  if (color != null && on) {
    await transport.setColor(
      color,
      current['on'] == true ? _transition(config) : 0,
    );
  }
  if (on != (current['on'] == true) || !on) {
    await transport.setPower(on, _transition(config));
  }
  return {
    'updated': true,
    'on': on,
    if (color != null) 'color': config['color'],
  };
}

int _transition(RuntimeMap config) =>
    (_number(config['transition'], 0.5) * 1000).clamp(0, 600000).round();

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
