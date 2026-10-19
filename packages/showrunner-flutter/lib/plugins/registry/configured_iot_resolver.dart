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
    resourceType: resourceType,
    secretSettings: dataService.secretSettingsStore,
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
  final requestedState = device['on'] ?? device['state'] ?? 'on';
  final state = _iotState(requestedState);
  final toggleAwareState = _iotStateOrToggle(requestedState);
  final color = device['color'] ?? device['lightColor'];
  final transition = device['transition'] ?? 0.5;

  switch (provider) {
    case 'govee':
      if (resourceType == 'Plug' || !hasColor) {
        return registry.invokeActionKey(
          const ActionKey(
            plugin: PluginId('govee'),
            action: ActionId('setPower'),
          ),
          {
            'device': providerId,
            'model': _requiredDeviceField(device, 'model', resourceId),
            'state': state,
          },
          context: context,
        );
      }
      if (hasPower) {
        await registry.invokeActionKey(
          const ActionKey(
            plugin: PluginId('govee'),
            action: ActionId('setPower'),
          ),
          {
            'device': providerId,
            'model': _requiredDeviceField(device, 'model', resourceId),
            'state': state,
          },
          context: context,
        );
      }
      return registry.invokeActionKey(
        const ActionKey(
          plugin: PluginId('govee'),
          action: ActionId('setColor'),
        ),
        {
          'device': providerId,
          'model': _requiredDeviceField(device, 'model', resourceId),
          'color': color,
        },
        context: context,
      );
    case 'philips-hue':
      if (resourceType == 'Plug') {
        return registry.invokeActionKey(
          const ActionKey(
            plugin: PluginId('philips-hue'),
            action: ActionId('setPlugState'),
          ),
          {
            if (device['host']?.toString().trim().isNotEmpty == true)
              'host': device['host'],
            if (device['hubKey']?.toString().trim().isNotEmpty == true)
              'hubKey': device['hubKey'],
            'lightId': providerId,
            'state': toggleAwareState,
          },
          context: context,
        );
      }
      final hueResourceType = device['resourceType']?.toString().trim();
      return registry.invokeActionKey(
        const ActionKey(
          plugin: PluginId('philips-hue'),
          action: ActionId('setLightState'),
        ),
        {
          if (device['host']?.toString().trim().isNotEmpty == true)
            'host': device['host'],
          if (device['hubKey']?.toString().trim().isNotEmpty == true)
            'hubKey': device['hubKey'],
          'lightId': providerId,
          'resourceType': hueResourceType?.isNotEmpty == true
              ? hueResourceType
              : device['hueType']?.toString().trim().toLowerCase() == 'group'
              ? 'grouped_light'
              : 'light',
          'state': toggleAwareState,
          'color': color,
          'transition': transition,
        },
        context: context,
      );
    case 'twinkly':
      if (resourceType != 'Light') {
        throw UnsupportedError('Twinkly plug resources are not supported.');
      }
      final ip = _deviceHost(device, resourceId);
      if (hasPower && !state) {
        return registry.invokeActionKey(
          const ActionKey(
            plugin: PluginId('twinkly'),
            action: ActionId('turnOff'),
          ),
          {'ip': ip},
          context: context,
        );
      }
      if (!hasColor) {
        throw UnsupportedError(
          'Twinkly can only turn on through a color or movie.',
        );
      }
      return registry.invokeActionKey(
        const ActionKey(
          plugin: PluginId('twinkly'),
          action: ActionId('setColor'),
        ),
        {'ip': ip, 'color': color},
        context: context,
      );
    case 'elgato':
      if (resourceType != 'Light') {
        throw UnsupportedError('Elgato plug resources are not supported.');
      }
      return registry.invokeActionKey(
        const ActionKey(
          plugin: PluginId('elgato'),
          action: ActionId('setLightState'),
        ),
        {
          'host': _deviceHost(device, resourceId),
          'port': _positiveDeviceInt(device['port'], 9123),
          'state': state,
          'color': color,
          'numberOfLights': _positiveDeviceInt(device['numberOfLights'], 1),
        },
        context: context,
      );
    // The plugin ID is `tplink-kasa`, while resources created by the
    // Some provider configurations persist the shorter provider value `kasa`.
    case 'kasa':
    case 'tplink-kasa':
      return registry.invokeActionKey(
        ActionKey(
          plugin: const PluginId('tplink-kasa'),
          action: ActionId(
            resourceType == 'Plug' ? 'setPlugState' : 'setLightState',
          ),
        ),
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
        return registry.invokeActionKey(
          const ActionKey(
            plugin: PluginId('lifx'),
            action: ActionId('setPower'),
          ),
          {
            'host': _deviceHost(device, resourceId),
            'port': _positiveDeviceInt(device['port'], 56700),
            if (device['target']?.toString().trim().isNotEmpty == true)
              'target': device['target'],
            'state': state,
            'transition': transition,
          },
          context: context,
        );
      }
      return registry.invokeActionKey(
        const ActionKey(
          plugin: PluginId('lifx'),
          action: ActionId('setLightState'),
        ),
        {
          'host': _deviceHost(device, resourceId),
          'port': _positiveDeviceInt(device['port'], 56700),
          if (device['target']?.toString().trim().isNotEmpty == true)
            'target': device['target'],
          'state': state,
          'color': color,
          'transition': transition,
        },
        context: context,
      );
    case 'wyze':
      return registry.invokeActionKey(
        ActionKey(
          plugin: const PluginId('wyze'),
          action: ActionId(
            resourceType == 'Plug' ? 'setPlugState' : 'setLightState',
          ),
        ),
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

Object _iotStateOrToggle(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  if (text == 'toggle') return 'toggle';
  return _iotState(value);
}

int _positiveDeviceInt(Object? value, int fallback) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : fallback;
}
