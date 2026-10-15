import '../../components/data_inputs/numeric_input_formatter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/showrunner_graph_editor.dart';
import '../../app/app_feedback.dart';
import '../../app/name_dialog.dart';
import '../../design_system/tokens/tokens.dart';
import '../graph/graph_workspace.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/registry/builtin_resource_specs.dart';
import '../../runtime/expression.dart';
import '../../plugins/obs/transport.dart';
import '../../plugins/obs/overlay_source_service.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../schema/stream_plan.dart';
import '../../persistence/secret_settings_store.dart';
import 'color_field.dart';
import 'overlay/overlay_document.dart';
import 'overlay/overlay_snapping.dart';
import '../../components/data_inputs/data_input.dart';
import '../../components/data_inputs/overlay_style_inputs.dart';
import '../../plugins/sound/ui/tts_voice_provider_picker.dart';
import '../../plugins/overlays/shader_graph/shader_graph_editor.dart';
import '../../plugins/overlays/shader_graph/shader_graph_model.dart';
import '../../plugins/overlays/generated_widget_catalog.dart';
import '../../plugins/overlays/overlay_widget_icons.dart';
import '../../plugins/overlays/overlay_presence.dart';
import '../../plugins/dashboards/ui/dashboard_widget_config.dart';
import '../../services/oauth_token.dart';

part 'overlay/overlay_editor.dart';
part 'overlay/overlay_canvas.dart';
part 'overlay/overlay_widget_inspector.dart';
part 'stream_plan/stream_plan_editor.dart';
part 'overlay/overlay_widget_config_editor.dart';
part 'stream_plan/stream_plan_segment_editor.dart';
part 'dashboard/dashboard_editor.dart';
part 'variable/variable_editor.dart';
part 'connection/connection_editor.dart';
part 'sound/tts_voice_editor.dart';
part 'sound/audio_splitter_editor.dart';
part 'twitch/viewer_group_editor.dart';
part 'twitch/channel_point_reward_editor.dart';
part 'spellcast/spellcast_editor.dart';
part 'connection/map_resource_editor.dart';

List<JsonMap> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <JsonMap>[];

void _moveListItem<T>(List<T> items, int from, int to) {
  if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
    return;
  }
  final item = items.removeAt(from);
  items.insert(to, item);
}

List<String> _strings(Object? value) =>
    value is List ? value.map((item) => item.toString()).toList() : <String>[];

String _widgetTitle(
  JsonMap widget, [
  List<GeneratedOverlayWidget> catalog = const [],
]) {
  final name = widget['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  final config = widget['config'];
  if (config is Map && config['label']?.toString().trim().isNotEmpty == true) {
    return config['label'].toString();
  }
  for (final definition in catalog) {
    if (definition.pluginId == _definitionPluginId(widget) &&
        definition.id == _definitionWidgetId(widget)) {
      return definition.name;
    }
  }
  return widget['title']?.toString() ??
      widget['widget']?.toString() ??
      'Widget';
}

String _definitionPluginId(JsonMap widget) =>
    widget['plugin']?.toString() ?? '';

String _definitionWidgetId(JsonMap widget) =>
    widget['widget']?.toString() ?? '';

int _dashboardIdCounter = 0;
int _audioSplitIdCounter = 0;

String _newDashboardId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_dashboardIdCounter++}';

String _dashboardId(Object? value, String prefix) {
  final id = value?.toString().trim();
  return id == null || id.isEmpty ? _newDashboardId(prefix) : id;
}

String _dashboardValue(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _audioSplitId(Object? value) {
  final id = value?.toString().trim();
  return id == null || id.isEmpty
      ? 'split-${DateTime.now().microsecondsSinceEpoch}-${_audioSplitIdCounter++}'
      : id;
}

JsonMap _audioSplit(Map value) => {
  ...Map<String, dynamic>.from(value),
  'id': _audioSplitId(value['id']),
  'mute': value['mute'] == true,
  'volume': ((value['volume'] as num?)?.toDouble() ?? 100).clamp(0, 100),
};

JsonMap _dashboardWidget(Map value) {
  final size = value['size'] is Map
      ? Map<String, dynamic>.from(value['size'] as Map)
      : const <String, dynamic>{};
  final config = value['config'] is Map
      ? Map<String, dynamic>.from(value['config'] as Map)
      : <String, dynamic>{
          'label': value['title']?.toString() ?? 'New widget',
          'color': '#000000',
        };
  return {
    ...Map<String, dynamic>.from(value),
    'id': _dashboardId(value['id'], 'widget'),
    'plugin': _dashboardValue(value['plugin'], 'dashboards'),
    'widget': _dashboardValue(value['widget'], 'label'),
    'size': {
      'width': (size['width'] as num?)?.toInt() ?? 4,
      'height': (size['height'] as num?)?.toInt() ?? 1,
    },
    'config': config,
  };
}

JsonMap _dashboardSection(Map value) {
  final widgets = _maps(value['widgets']).map(_dashboardWidget).toList();
  return {
    ...Map<String, dynamic>.from(value),
    'id': _dashboardId(value['id'], 'section'),
    'name': value['name']?.toString() ?? 'New section',
    'columns': (value['columns'] as num?)?.toInt() ?? 4,
    'widgets': widgets,
  };
}

JsonMap _dashboardPage(Map value) {
  final sections = _maps(value['sections']).map(_dashboardSection).toList();
  return {
    ...Map<String, dynamic>.from(value),
    'id': _dashboardId(value['id'], 'page'),
    'name': value['name']?.toString() ?? 'New page',
    'sections': sections,
  };
}

typedef DartResourceEditorBuilder =
    Widget Function(
      BuildContext context,
      ResourceData resource,
      Future<void> Function(ResourceData resource) onSave,
    );

typedef DartResourceEditorRuntimeBuilder =
    Widget Function(
      BuildContext context,
      ResourceData resource,
      Future<void> Function(ResourceData resource) onSave, {
      required Future<DartPluginRegistry> registryFuture,
      required GraphResourceOptionsLoader resourceOptionsLoader,
    });

final class DartResourceEditorDefinition implements DartResourceContract {
  DartResourceEditorDefinition.fromContract({
    required DartResourceContract contract,
    required this.builder,
    this.runtimeBuilder,
  }) : pluginId = contract.ownerId.value,
       resourceType = contract.resourceTypeId.value,
       displayName = contract.displayName,
       storageDirectory = contract.storageDirectory,
       defaultConfig = contract.createDefaultConfig;

  final String pluginId;
  final String resourceType;
  @override
  final String displayName;
  @override
  final String storageDirectory;
  final JsonMap Function(String name) defaultConfig;
  final DartResourceEditorBuilder builder;
  final DartResourceEditorRuntimeBuilder? runtimeBuilder;

  @override
  PluginId get ownerId => PluginId(pluginId);

  @override
  ResourceTypeId get resourceTypeId => ResourceTypeId(resourceType);

  @override
  RuntimeMap createDefaultConfig(String name) => defaultConfig(name);

  ResourceTypeId get key => resourceTypeId;
}

final class DartResourceEditorRegistry {
  final _editors = <ResourceTypeId, DartResourceEditorDefinition>{};

  void register(DartResourceEditorDefinition definition) {
    if (definition.pluginId.isEmpty) {
      throw ArgumentError.value(definition.pluginId, 'definition.pluginId');
    }
    if (definition.resourceType.isEmpty) {
      throw ArgumentError.value(
        definition.resourceType,
        'definition.resourceType',
      );
    }
    if (_editors.containsKey(definition.key)) {
      throw ArgumentError(
        'Resource editor is registered more than once: ${definition.resourceType}',
      );
    }
    _editors[definition.key] = definition;
  }

  DartResourceEditorDefinition? find(String resourceType) =>
      _editors[ResourceTypeId(resourceType)];

  Iterable<DartResourceEditorDefinition> get definitions =>
      List.unmodifiable(_editors.values);
}

DartResourceEditorRegistry createDefaultResourceEditorRegistry() {
  final registry = DartResourceEditorRegistry();
  registry.register(
    DartResourceEditorDefinition.fromContract(
      contract: builtInResourceSpec('Overlay'),
      builder: (context, resource, onSave) =>
          OverlayEditorPage(resource: resource, onSave: onSave),
    ),
  );
  registry.register(
    DartResourceEditorDefinition.fromContract(
      contract: builtInResourceSpec('StreamPlan'),
      builder: (context, resource, onSave) =>
          StreamPlanEditorPage(resource: resource, onSave: onSave),
      runtimeBuilder:
          (
            context,
            resource,
            onSave, {
            required registryFuture,
            required resourceOptionsLoader,
          }) => StreamPlanEditorPage(
            resource: resource,
            onSave: onSave,
            registryFuture: registryFuture,
            resourceOptionsLoader: resourceOptionsLoader,
          ),
    ),
  );
  registry.register(
    DartResourceEditorDefinition.fromContract(
      contract: builtInResourceSpec('Variable'),
      builder: (context, resource, onSave) =>
          _VariableEditor(resource: resource, onSave: onSave),
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'obs',
      resourceType: 'OBSConnection',
      displayName: 'OBS Connection',
      storageDirectory: 'obs/connections',
      defaultConfig: (name) => {
        'name': name,
        'host': '127.0.0.1',
        'port': 4455,
        'local': true,
      },
      fields: const [
        'name',
        'host',
        'port',
        'password',
        'installPath',
        'local',
      ],
      runtimeBuilder:
          (
            context,
            resource,
            onSave, {
            required registryFuture,
            required resourceOptionsLoader,
          }) => _ConnectionEditor(
            title: 'Edit OBS connection',
            resource: resource,
            onSave: onSave,
            supportsLocal: true,
            testConnection: _testObsConnection,
          ),
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'minecraft',
      resourceType: 'RCONConnection',
      displayName: 'RCON Connection',
      storageDirectory: 'minecraft/connections',
      defaultConfig: (name) => {
        'name': name,
        'host': '127.0.0.1',
        'port': 25575,
      },
      fields: const ['name', 'host', 'port', 'password'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'sound',
      resourceType: 'TTSVoice',
      displayName: 'TTS Voice',
      storageDirectory: 'sound/tts',
      defaultConfig: (name) => {
        'name': name,
        'voiceProvider': '',
        'providerConfig': {},
      },
      fields: const ['name', 'voiceProvider', 'providerConfig'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'twitch',
      resourceType: 'CustomTwitchViewerGroup',
      displayName: 'Twitch Viewer Group',
      storageDirectory: 'twitch/groups',
      defaultConfig: (name) => {'name': name, 'userIds': <String>[]},
      fields: const ['name', 'userIds'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'twitch',
      resourceType: 'TwitchAccount',
      displayName: 'Twitch Account',
      storageDirectory: 'accounts/twitch',
      defaultConfig: (name) => {
        'name': name,
        'twitchId': '',
        'isAffiliate': false,
        'isPartner': false,
        'email': '',
      },
      fields: const [
        'name',
        'twitchId',
        'isAffiliate',
        'isPartner',
        'email',
        'accessToken',
        'refreshToken',
      ],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'discord',
      resourceType: 'DiscordWebhook',
      displayName: 'Discord Webhook',
      storageDirectory: 'discord/webhooks',
      defaultConfig: (name) => {'name': name, 'webhookUrl': ''},
      fields: const ['name', 'webhookUrl'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'bluesky',
      resourceType: 'BlueSkyAccount',
      displayName: 'BlueSky Account',
      storageDirectory: 'accounts/bluesky',
      defaultConfig: (name) => {
        'name': name,
        'identifier': '',
        'appPassword': '',
      },
      fields: const ['name', 'identifier', 'appPassword'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'dashboards',
      resourceType: 'Dashboard',
      displayName: 'Dashboard',
      storageDirectory: 'dashboards',
      defaultConfig: (name) => {
        'name': name,
        'pages': <JsonMap>[],
        'remoteTwitchIds': <String>[],
        'resourceSlots': <JsonMap>[],
      },
      fields: const ['name'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'spellcast',
      resourceType: 'SpellHook',
      displayName: 'Spellcast Spell',
      storageDirectory: 'spellcast/spells',
      defaultConfig: (name) => {
        'name': name,
        'spellId': '',
        'spellData': {
          'enabled': false,
          'description': '',
          'bits': 10,
          'color': '#719ece',
        },
      },
      fields: const ['name', 'spellId'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'sound',
      resourceType: 'AudioSplitterOutput',
      displayName: 'Audio Splitter',
      storageDirectory: 'sound/splitters',
      defaultConfig: (name) => {
        'name': name,
        'type': 'splitter',
        'redirects': <JsonMap>[],
      },
      fields: const ['name'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'sound',
      resourceType: 'SoundOutput',
      displayName: 'Sound Output',
      storageDirectory: 'sound/outputs',
      defaultConfig: (name) => {
        'name': name,
        'type': 'system',
        'deviceId': '',
        'isDefault': false,
      },
      fields: const [
        'name',
        'type',
        'deviceId',
        'webId',
        'isDefault',
        'overlayId',
      ],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'sound',
      resourceType: 'TTSVoiceProvider',
      displayName: 'TTS Voice Provider',
      storageDirectory: 'sound/tts-providers',
      defaultConfig: (name) => {
        'name': name,
        'provider': '',
        'providerId': '',
        'config': <String, dynamic>{},
      },
      fields: const ['name', 'provider', 'providerId', 'config'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'twitch',
      resourceType: 'ChannelPointReward',
      displayName: 'Twitch Channel Point Reward',
      storageDirectory: 'twitch/channelpoints',
      defaultConfig: (name) => {
        'name': name,
        'twitchId': '',
        'controllable': true,
        'transient': false,
        'allowEnable': true,
        'rewardData': {
          'prompt': '',
          'backgroundColor': '#9147ff',
          'userInputRequired': false,
          'cost': 100,
          'cooldown': null,
          'maxRedemptionsPerStream': null,
          'maxRedemptionsPerUserPerStream': null,
          'skipQueue': false,
        },
      },
      fields: const ['name', 'twitchId'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'iot',
      resourceType: 'Light',
      displayName: 'Smart Light',
      storageDirectory: 'iot/lights',
      defaultConfig: (name) => {
        'name': name,
        'provider': '',
        'providerId': '',
        'host': '',
        'ip': '',
        'hubKey': '',
        'model': '',
        'resourceType': 'light',
        'target': '',
        'rgbAvailable': true,
        'kelvinAvailable': true,
        'dimmingAvailable': true,
        'transitionsAvailable': true,
      },
      fields: const [
        'name',
        'provider',
        'providerId',
        'host',
        'ip',
        'hubKey',
        'model',
        'resourceType',
        'target',
        'numberOfLights',
        'ledCount',
        'rgbAvailable',
        'kelvinAvailable',
        'dimmingAvailable',
        'transitionsAvailable',
      ],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'iot',
      resourceType: 'Plug',
      displayName: 'Smart Plug',
      storageDirectory: 'iot/plugs',
      defaultConfig: (name) => {
        'name': name,
        'provider': '',
        'providerId': '',
        'host': '',
        'ip': '',
        'model': '',
      },
      fields: const ['name', 'provider', 'providerId', 'host', 'ip', 'model'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'input',
      resourceType: 'Gamepad',
      displayName: 'Gamepad',
      storageDirectory: 'input/gamepads',
      defaultConfig: (name) => {'name': name, 'id': ''},
      fields: const ['name', 'id', 'index'],
    ),
  );
  registry.register(
    _pluginDefinition(
      pluginId: 'wyze',
      resourceType: 'WyzeAccount',
      displayName: 'Wyze Account',
      storageDirectory: 'accounts/wyze',
      defaultConfig: (name) => {
        'name': name,
        'email': '',
        'scopes': <String>[],
      },
      fields: const ['name', 'email', 'scopes', 'accessToken', 'refreshToken'],
    ),
  );
  return registry;
}

DartResourceEditorDefinition _pluginDefinition({
  required String pluginId,
  required String resourceType,
  required String displayName,
  required String storageDirectory,
  required JsonMap Function(String name) defaultConfig,
  required List<String> fields,
  DartResourceEditorRuntimeBuilder? runtimeBuilder,
}) {
  final contract = builtInResourceSpec(resourceType);
  if (contract.ownerId.value != pluginId ||
      contract.displayName != displayName ||
      contract.storageDirectory != storageDirectory ||
      jsonEncode(contract.createDefaultConfig('probe')) !=
          jsonEncode(defaultConfig('probe'))) {
    throw StateError('Resource editor metadata drifted for $resourceType.');
  }
  return DartResourceEditorDefinition.fromContract(
    contract: contract,
    builder: (context, resource, onSave) => switch (resourceType) {
      'OBSConnection' => _ConnectionEditor(
        title: 'Edit OBS connection',
        resource: resource,
        onSave: onSave,
        supportsLocal: true,
      ),
      'RCONConnection' => _ConnectionEditor(
        title: 'Edit RCON connection',
        resource: resource,
        onSave: onSave,
      ),
      'TTSVoice' => _TtsVoiceEditor(resource: resource, onSave: onSave),
      'AudioSplitterOutput' => _AudioSplitterEditor(
        resource: resource,
        onSave: onSave,
      ),
      'CustomTwitchViewerGroup' => _ViewerGroupEditor(
        resource: resource,
        onSave: onSave,
      ),
      'Dashboard' => _DashboardEditor(resource: resource, onSave: onSave),
      'SpellHook' => _SpellcastEditor(resource: resource, onSave: onSave),
      'ChannelPointReward' => _ChannelPointRewardEditor(
        resource: resource,
        onSave: onSave,
      ),
      'Light' => _MapResourceEditor(
        title: 'Edit smart light',
        resource: resource,
        fields: fields,
        secretFields: secretResourceFieldIdsFor(resourceType),
        onSave: onSave,
      ),
      'Plug' => _MapResourceEditor(
        title: 'Edit smart plug',
        resource: resource,
        fields: fields,
        secretFields: secretResourceFieldIdsFor(resourceType),
        onSave: onSave,
      ),
      _ => _MapResourceEditor(
        title: 'Edit $displayName',
        resource: resource,
        fields: fields,
        secretFields: secretResourceFieldIdsFor(resourceType),
        onSave: onSave,
      ),
    },
    runtimeBuilder: runtimeBuilder,
  );
}
