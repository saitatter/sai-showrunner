import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../services/showrunner_data_service.dart';
import '../iot/manifest.dart';
import 'plugin_registry.dart';

IotResourceActionResolver createConfiguredIotResolver({
  required DartPluginRegistry registry,
  required ShowRunnerDataService dataService,
}) => (resourceType, resourceId, actionConfig, context) async {
  final directory = resourceType == 'Light' ? 'iot/lights' : 'iot/plugs';
  final resource = await ResourceRepository(
    Directory('${dataService.userDirectory.path}/$directory'),
  ).load(resourceId);
  if (resource == null) {
    throw StateError('$resourceType resource "$resourceId" was not found.');
  }

  final device = <String, dynamic>{...resource.config, ...actionConfig};
  final provider = device['provider']?.toString().trim().toLowerCase() ?? '';
  if (provider.isEmpty) {
    throw StateError('$resourceType resource "$resourceId" has no provider.');
  }
  final providerId = device['providerId']?.toString().trim() ?? '';
  if (providerId.isEmpty) {
    throw StateError(
      '$resourceType resource "$resourceId" has no provider ID.',
    );
  }

  final hasColor = device['color']?.toString().trim().isNotEmpty == true;
  final hasPower = device.containsKey('on') || device.containsKey('state');
  final state = _iotState(device['on'] ?? device['state'] ?? 'on');
  final color = device['color'] ?? device['lightColor'];
  final transition = device['transition'] ?? 0.5;

  switch (provider) {
    case 'govee':
      if (resourceType == 'Plug' || !hasColor) {
        return registry.invokeAction('govee', 'setPower', {
          'device': providerId,
          'model': _requiredDeviceField(device, 'model', resourceId),
          'state': state,
        }, context: context);
      }
      if (hasPower) {
        await registry.invokeAction('govee', 'setPower', {
          'device': providerId,
          'model': _requiredDeviceField(device, 'model', resourceId),
          'state': state,
        }, context: context);
      }
      return registry.invokeAction('govee', 'setColor', {
        'device': providerId,
        'model': _requiredDeviceField(device, 'model', resourceId),
        'color': color,
      }, context: context);
    case 'philips-hue':
      if (resourceType != 'Light') {
        throw UnsupportedError('Philips Hue plug resources are not supported.');
      }
      return registry.invokeAction('philips-hue', 'setLightState', {
        if (device['host']?.toString().trim().isNotEmpty == true)
          'host': device['host'],
        if (device['hubKey']?.toString().trim().isNotEmpty == true)
          'hubKey': device['hubKey'],
        'lightId': providerId,
        'resourceType': device['resourceType'] ?? 'light',
        'state': state,
        'color': color,
        'transition': transition,
      }, context: context);
    case 'twinkly':
      if (resourceType != 'Light') {
        throw UnsupportedError('Twinkly plug resources are not supported.');
      }
      final ip = _deviceHost(device, resourceId);
      if (hasPower && !state) {
        return registry.invokeAction('twinkly', 'turnOff', {
          'ip': ip,
        }, context: context);
      }
      if (!hasColor) {
        throw UnsupportedError(
          'Twinkly can only turn on through a color or movie.',
        );
      }
      return registry.invokeAction('twinkly', 'setColor', {
        'ip': ip,
        'color': color,
      }, context: context);
    case 'elgato':
      if (resourceType != 'Light') {
        throw UnsupportedError('Elgato plug resources are not supported.');
      }
      return registry.invokeAction('elgato', 'setLightState', {
        'host': _deviceHost(device, resourceId),
        'port': _positiveDeviceInt(device['port'], 9123),
        'state': state,
        'color': color,
        'numberOfLights': _positiveDeviceInt(device['numberOfLights'], 1),
      }, context: context);
    // The plugin ID is `tplink-kasa`, while resources created by the
    // reference Electron plugin persist the shorter provider value `kasa`.
    case 'kasa':
    case 'tplink-kasa':
      return registry.invokeAction(
        'tplink-kasa',
        resourceType == 'Plug' ? 'setPlugState' : 'setLightState',
        {
          'host': _deviceHost(device, resourceId),
          'port': _positiveDeviceInt(device['port'], 9999),
          'state': state,
          if (resourceType == 'Light') ...{
            'color': color,
            'transition': transition,
          },
        },
        context: context,
      );
    case 'lifx':
      if (resourceType != 'Light') {
        throw UnsupportedError('LIFX plug resources are not supported.');
      }
      if (hasPower && !hasColor) {
        return registry.invokeAction('lifx', 'setPower', {
          'host': _deviceHost(device, resourceId),
          'port': _positiveDeviceInt(device['port'], 56700),
          if (device['target']?.toString().trim().isNotEmpty == true)
            'target': device['target'],
          'state': state,
          'transition': transition,
        }, context: context);
      }
      return registry.invokeAction('lifx', 'setLightState', {
        'host': _deviceHost(device, resourceId),
        'port': _positiveDeviceInt(device['port'], 56700),
        if (device['target']?.toString().trim().isNotEmpty == true)
          'target': device['target'],
        'state': state,
        'color': color,
        'transition': transition,
      }, context: context);
    case 'wyze':
      return registry.invokeAction(
        'wyze',
        resourceType == 'Plug' ? 'setPlugState' : 'setLightState',
        {
          'device': providerId,
          'model': _requiredDeviceField(device, 'model', resourceId),
          'state': state,
          if (resourceType == 'Light') 'color': color,
        },
        context: context,
      );
    default:
      throw UnsupportedError(
        'IoT provider "$provider" has no Flutter resource dispatcher.',
      );
  }
};

String _requiredDeviceField(
  Map<String, dynamic> config,
  String field,
  String resourceId,
) {
  final value = config[field]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw StateError('IoT resource "$resourceId" has no $field.');
  }
  return value;
}

String _deviceHost(Map<String, dynamic> config, String resourceId) {
  final host = config['ip']?.toString().trim().isNotEmpty == true
      ? config['ip'].toString().trim()
      : config['host']?.toString().trim() ?? '';
  if (host.isEmpty) throw StateError('IoT resource "$resourceId" has no IP.');
  return host;
}

bool _iotState(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text != 'false' && text != 'off' && text != '0';
}

int _positiveDeviceInt(Object? value, int fallback) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : fallback;
}
