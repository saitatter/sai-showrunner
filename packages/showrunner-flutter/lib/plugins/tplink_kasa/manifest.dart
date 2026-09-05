import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_contract.dart';

typedef KasaRequest = Future<RuntimeMap> Function(RuntimeMap request);

final class KasaTransport {
  const KasaTransport(this.request);

  final KasaRequest request;
}

final class KasaTcpTransport {
  const KasaTcpTransport({required this.host, this.port = 9999});

  final String host;
  final int port;

  Future<RuntimeMap> request(RuntimeMap payload) async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 2),
    );
    try {
      final responseFuture = _readFrame(socket);
      socket.add(encodeKasaFrame(jsonEncode(payload)));
      await socket.flush();
      final response = await responseFuture.timeout(const Duration(seconds: 5));
      final decoded = jsonDecode(decodeKasaPayload(response));
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } finally {
      await socket.close();
    }
  }
}

Uint8List encodeKasaFrame(String payload) {
  final encrypted = _xor(payload.codeUnits);
  final frame = Uint8List(encrypted.length + 4);
  ByteData.sublistView(frame).setUint32(0, encrypted.length);
  frame.setRange(4, frame.length, encrypted);
  return frame;
}

String decodeKasaPayload(List<int> encrypted) =>
    utf8.decode(_xor(encrypted, decode: true));

const _sysInfo = <String, dynamic>{
  'system': {'get_sysinfo': <String, dynamic>{}},
};

const _lightSchema = DartDataInputSchema(
  label: 'Kasa light state',
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
      label: 'Device Port',
      key: 'port',
      kind: DartDataInputKind.number,
      defaultValue: 9999,
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

const _plugSchema = DartDataInputSchema(
  label: 'Kasa plug state',
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
      label: 'Device Port',
      key: 'port',
      kind: DartDataInputKind.number,
      defaultValue: 9999,
    ),
  ],
);

typedef KasaTransportResolver = KasaTransport Function(RuntimeMap config);

DartPluginManifest createKasaPlugin(
  KasaTransport transport, {
  KasaTransportResolver? transportResolver,
}) => DartPluginManifest(
  id: 'tplink-kasa',
  name: 'TP-Link Kasa',
  settings: const [
    DartSettingDefinition(id: 'host', displayName: 'Device IP / Host'),
    DartSettingDefinition(
      id: 'port',
      displayName: 'Device Port',
      defaultValue: 9999,
    ),
    DartSettingDefinition(
      id: 'subnetMask',
      displayName: 'Discovery Subnet Mask',
      defaultValue: '255.255.255.255',
    ),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'tplink-kasa',
      actionId: 'getDeviceInfo',
      displayName: 'Get Device Info',
      invoke: (config, context) =>
          (transportResolver?.call(config) ?? transport).request(_sysInfo),
    ),
    DartActionDefinition(
      pluginId: 'tplink-kasa',
      actionId: 'getLightState',
      displayName: 'Get Light State',
      invoke: (config, context) =>
          (transportResolver?.call(config) ?? transport).request(_sysInfo),
    ),
    DartActionDefinition(
      pluginId: 'tplink-kasa',
      actionId: 'setLightState',
      displayName: 'Set Light State',
      configSchema: _lightSchema,
      invoke: (config, context) =>
          _setLightState(transportResolver?.call(config) ?? transport, config),
    ),
    DartActionDefinition(
      pluginId: 'tplink-kasa',
      actionId: 'setPlugState',
      displayName: 'Set Plug State',
      configSchema: _plugSchema,
      invoke: (config, context) =>
          _setPlugState(transportResolver?.call(config) ?? transport, config),
    ),
  ],
);

Future<Object?> _setLightState(
  KasaTransport transport,
  RuntimeMap config,
) async {
  var state = config['state'] ?? 'on';
  RuntimeMap? current;
  if (state == 'toggle' || config['color'] == null) {
    current = await transport.request(_sysInfo);
  }
  if (state == 'toggle') state = !_isOn(current ?? const {});
  final update = <String, dynamic>{
    'on_off': state == true || state == 'on' ? 1 : 0,
    'transition_period': (_number(config['transition'], 0.5) * 1000)
        .clamp(0, 600000)
        .round(),
  };
  final color = parseLightColor(config['color']?.toString());
  if (color != null) {
    update['brightness'] = color.brightness.clamp(0, 100).round();
    if (color.isKelvin) {
      update['color_temp'] = color.kelvin!.round();
      update['hue'] = 0;
      update['saturation'] = 0;
    } else {
      update['hue'] = color.hue!.floor();
      update['saturation'] = color.saturation!.ceil();
      update['color_temp'] = 0;
    }
  }
  return transport.request({
    'smartlife.iot.smartbulb.lightingservice': {
      'transition_light_state': update,
    },
  });
}

Future<Object?> _setPlugState(
  KasaTransport transport,
  RuntimeMap config,
) async {
  var state = config['state'] ?? 'on';
  if (state == 'toggle') {
    final current = await transport.request(_sysInfo);
    state = !_isOn(current);
  }
  return transport.request({
    'system': {
      'set_relay_state': {'state': state == true || state == 'on' ? 1 : 0},
    },
  });
}

bool _isOn(RuntimeMap response) {
  final system = response['system'];
  final info = system is Map ? system['get_sysinfo'] : null;
  final value = info is Map ? info['relay_state'] ?? info['device_on'] : null;
  return value == true || value == 1;
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

Future<List<int>> _readFrame(Socket socket) {
  final completer = Completer<List<int>>();
  final buffer = <int>[];
  StreamSubscription<List<int>>? subscription;
  subscription = socket.listen(
    (chunk) {
      buffer.addAll(chunk);
      if (buffer.length < 4) return;
      final length = ByteData.sublistView(
        Uint8List.fromList(buffer),
      ).getUint32(0);
      if (length > 1024 * 1024 || buffer.length < length + 4) return;
      if (!completer.isCompleted) {
        completer.complete(buffer.sublist(4, length + 4));
        unawaited(subscription?.cancel());
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Kasa socket closed before a response.'),
        );
      }
    },
    cancelOnError: false,
  );
  return completer.future;
}

List<int> _xor(List<int> bytes, {bool decode = false}) {
  var key = 171;
  final result = <int>[];
  for (final byte in bytes) {
    if (decode) {
      result.add(byte ^ key);
      key = byte;
    } else {
      final encrypted = byte ^ key;
      result.add(encrypted);
      key = encrypted;
    }
  }
  return result;
}
