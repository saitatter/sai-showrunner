import 'dart:convert';
import 'package:flutter/material.dart';

import '../../editor/showrunner_graph_editor.dart';
import '../graph/graph_workspace.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/obs/transport.dart';
import '../../plugins/contracts/identifiers.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../schema/stream_plan.dart';
import 'media_picker.dart';
import 'color_field.dart';
import '../../components/data_inputs/data_input.dart';
import '../../plugins/sound/ui/tts_voice_provider_picker.dart';
import '../../plugins/overlays/ui/overlay_widget_config.dart';
import '../../plugins/dashboards/ui/dashboard_widget_config.dart';

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

String _widgetTitle(JsonMap widget) {
  final config = widget['config'];
  if (config is Map && config['label']?.toString().trim().isNotEmpty == true) {
    return config['label'].toString();
  }
  return widget['title']?.toString() ??
      widget['widget']?.toString() ??
      widget['type']?.toString() ??
      'Widget';
}

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

final class DartResourceEditorDefinition {
  const DartResourceEditorDefinition({
    required this.pluginId,
    required this.resourceType,
    required this.displayName,
    required this.storageDirectory,
    required this.defaultConfig,
    required this.builder,
    this.runtimeBuilder,
  });

  final String pluginId;
  final String resourceType;
  final String displayName;
  final String storageDirectory;
  final JsonMap Function(String name) defaultConfig;
  final DartResourceEditorBuilder builder;
  final DartResourceEditorRuntimeBuilder? runtimeBuilder;

  ResourceTypeId get key => ResourceTypeId(resourceType);
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
    DartResourceEditorDefinition(
      pluginId: 'showrunner',
      resourceType: 'Overlay',
      displayName: 'Overlay',
      storageDirectory: 'overlays',
      defaultConfig: (name) => {
        'name': name,
        'size': {'width': 1920, 'height': 1080},
        'widgets': [],
      },
      builder: (context, resource, onSave) =>
          _OverlayEditor(resource: resource, onSave: onSave),
    ),
  );
  registry.register(
    DartResourceEditorDefinition(
      pluginId: 'stream-plans',
      resourceType: 'StreamPlan',
      displayName: 'Stream Plan',
      storageDirectory: 'stream-plans',
      defaultConfig: (name) => {
        'name': name,
        'activationAutomation': emptyInlineAutomation(),
        'deactivationAutomation': emptyInlineAutomation(),
        'segments': [],
      },
      builder: (context, resource, onSave) =>
          _StreamPlanEditor(resource: resource, onSave: onSave),
      runtimeBuilder:
          (
            context,
            resource,
            onSave, {
            required registryFuture,
            required resourceOptionsLoader,
          }) => _StreamPlanEditor(
            resource: resource,
            onSave: onSave,
            registryFuture: registryFuture,
            resourceOptionsLoader: resourceOptionsLoader,
          ),
    ),
  );
  registry.register(
    DartResourceEditorDefinition(
      pluginId: 'showrunner',
      resourceType: 'Variable',
      displayName: 'Variable',
      storageDirectory: 'variables',
      defaultConfig: (name) => {
        'name': name,
        'type': 'string',
        'defaultValue': '',
        'persistent': true,
      },
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
}) => DartResourceEditorDefinition(
  pluginId: pluginId,
  resourceType: resourceType,
  displayName: displayName,
  storageDirectory: storageDirectory,
  defaultConfig: defaultConfig,
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
      onSave: onSave,
    ),
    'Plug' => _MapResourceEditor(
      title: 'Edit smart plug',
      resource: resource,
      fields: fields,
      onSave: onSave,
    ),
    _ => _MapResourceEditor(
      title: 'Edit $displayName',
      resource: resource,
      fields: fields,
      onSave: onSave,
    ),
  },
  runtimeBuilder: runtimeBuilder,
);

class _OverlayEditor extends StatefulWidget {
  const _OverlayEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_OverlayEditor> createState() => _OverlayEditorState();
}

class _OverlayEditorState extends State<_OverlayEditor> {
  late final TextEditingController _name;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _previewSource;
  late final TextEditingController _previewOffsetX;
  late final TextEditingController _previewOffsetY;
  late List<JsonMap> _widgets;
  late bool _previewEnabled;
  late bool _previewFromObs;

  @override
  void initState() {
    super.initState();
    final overlay = OverlayResource.fromResource(widget.resource);
    _name = TextEditingController(text: overlay.name);
    _width = TextEditingController(text: '${overlay.width}');
    _height = TextEditingController(text: '${overlay.height}');
    final preview = widget.resource.config['preview'] is Map
        ? Map<String, dynamic>.from(widget.resource.config['preview'] as Map)
        : const <String, dynamic>{};
    _previewEnabled = widget.resource.config['preview'] is Map;
    _previewFromObs = preview['source']?.toString() == 'obs';
    _previewSource = TextEditingController(
      text: _previewFromObs ? '' : '${preview['source'] ?? ''}',
    );
    _previewOffsetX = TextEditingController(text: '${preview['offsetX'] ?? 0}');
    _previewOffsetY = TextEditingController(text: '${preview['offsetY'] ?? 0}');
    _widgets = overlay.widgets
        .map((widget) => <String, dynamic>{...widget})
        .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _previewSource.dispose();
    _previewOffsetX.dispose();
    _previewOffsetY.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit overlay',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _width,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Width'),
      ),
      TextField(
        controller: _height,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Height'),
      ),
      const SizedBox(height: 8),
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Canvas presets',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          _sizePreset('1080p', 1920, 1080),
          _sizePreset('1440p', 2560, 1440),
          _sizePreset('4K', 3840, 2160),
          _sizePreset('Vertical', 1080, 1920),
        ],
      ),
      ExpansionTile(
        title: const Text('Preview'),
        initiallyExpanded: _previewEnabled,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable preview'),
            value: _previewEnabled,
            onChanged: (value) => setState(() => _previewEnabled = value),
          ),
          if (_previewEnabled) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preview OBS output'),
              value: _previewFromObs,
              onChanged: (value) => setState(() => _previewFromObs = value),
            ),
            if (!_previewFromObs)
              TextField(
                controller: _previewSource,
                decoration: const InputDecoration(
                  labelText: 'Preview image',
                  hintText: 'Optional PNG/JPG/BMP/WebP path',
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _previewOffsetX,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Offset X'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _previewOffsetY,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Offset Y'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Widgets',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add widget',
            onPressed: _addWidget,
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      if (_widgets.isEmpty)
        const Text('No widgets defined.')
      else
        for (var index = 0; index < _widgets.length; index++)
          KeyedSubtree(
            key: ValueKey(_widgets[index]['id'] ?? index),
            child: _OverlayWidgetCard(
              index: index,
              widgetConfig: _widgets[index],
              onChanged: (key, value) =>
                  setState(() => _widgets[index][key] = value),
              onDelete: () => setState(() => _widgets.removeAt(index)),
              onMoveUp: index == 0 ? null : () => _moveWidget(index, -1),
              onMoveDown: index == _widgets.length - 1
                  ? null
                  : () => _moveWidget(index, 1),
            ),
          ),
    ],
    onSave: () {
      final config = <String, dynamic>{
        ...widget.resource.config,
        'name': _name.text.trim(),
        'size': {
          'width': int.tryParse(_width.text) ?? 1920,
          'height': int.tryParse(_height.text) ?? 1080,
        },
        'widgets': _widgets,
      };
      config.remove('width');
      config.remove('height');
      if (_previewEnabled) {
        config['preview'] = {
          'offsetX': num.tryParse(_previewOffsetX.text) ?? 0,
          'offsetY': num.tryParse(_previewOffsetY.text) ?? 0,
          if (_previewFromObs)
            'source': 'obs'
          else if (_previewSource.text.trim().isNotEmpty)
            'source': _previewSource.text.trim(),
        };
      } else {
        config.remove('preview');
      }
      return widget.onSave(
        ResourceData(id: widget.resource.id, config: config),
      );
    },
  );

  Widget _sizePreset(String label, int width, int height) => OutlinedButton(
    onPressed: () => setState(() {
      _width.text = '$width';
      _height.text = '$height';
    }),
    child: Text(label),
  );

  Future<void> _addWidget() async {
    final definition = await showDialog<OverlayWidgetDefinition>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add overlay widget'),
        children: [
          for (final option in overlayWidgetDefinitions)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.widgets_outlined),
                title: Text(option.name),
                subtitle: Text('${option.plugin}.${option.widget}'),
              ),
            ),
        ],
      ),
    );
    if (!mounted || definition == null) return;
    setState(() => _widgets.add(definition.createWidget()));
  }

  void _moveWidget(int index, int delta) {
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _widgets.length) return;
    setState(() {
      final widget = _widgets.removeAt(index);
      _widgets.insert(target, widget);
    });
  }
}

class _OverlayWidgetCard extends StatelessWidget {
  const _OverlayWidgetCard({
    required this.index,
    required this.widgetConfig,
    required this.onChanged,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final JsonMap widgetConfig;
  final void Function(String key, dynamic value) onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    if (widgetConfig.containsKey('plugin') ||
        widgetConfig.containsKey('widget')) {
      return _CanonicalOverlayWidgetCard(
        index: index,
        widgetConfig: widgetConfig,
        onChanged: onChanged,
        onDelete: onDelete,
        onMoveUp: onMoveUp,
        onMoveDown: onMoveDown,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Widget ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete widget',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _enumField('type', '${widgetConfig['type'] ?? 'text'}', const [
                  'text',
                  'image',
                  'video',
                  'audio',
                  'media',
                ], onChanged),
                _field('text', '${widgetConfig['text'] ?? ''}', onChanged),
                _mediaField(context),
                _field(
                  'x',
                  '${widgetConfig['x'] ?? 0}',
                  onChanged,
                  numeric: true,
                ),
                _field(
                  'y',
                  '${widgetConfig['y'] ?? 0}',
                  onChanged,
                  numeric: true,
                ),
                _field(
                  'width',
                  '${widgetConfig['width'] ?? 320}',
                  onChanged,
                  numeric: true,
                ),
                _field(
                  'height',
                  '${widgetConfig['height'] ?? 80}',
                  onChanged,
                  numeric: true,
                ),
                _field(
                  'opacity',
                  '${widgetConfig['opacity'] ?? 1}',
                  onChanged,
                  numeric: true,
                ),
                _field(
                  'fontSize',
                  '${widgetConfig['fontSize'] ?? 16}',
                  onChanged,
                  numeric: true,
                ),
                ColorValueField(
                  label: 'color',
                  initialValue: '${widgetConfig['color'] ?? '#ffffff'}',
                  onChanged: (value) => onChanged('color', value),
                ),
                ColorValueField(
                  label: 'backgroundColor',
                  initialValue:
                      '${widgetConfig['backgroundColor'] ?? 'transparent'}',
                  onChanged: (value) => onChanged('backgroundColor', value),
                ),
                _enumField(
                  'fontWeight',
                  '${widgetConfig['fontWeight'] ?? 'normal'}',
                  const ['normal', 'bold'],
                  onChanged,
                ),
                _enumField(
                  'textAlign',
                  '${widgetConfig['textAlign'] ?? 'left'}',
                  const ['left', 'center', 'right'],
                  onChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _enumField(
    String key,
    String value,
    List<String> options,
    void Function(String key, dynamic value) onChanged,
  ) => SizedBox(
    width: 120,
    child: DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : options.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: key),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: (next) {
        if (next != null) onChanged(key, next);
      },
    ),
  );

  Widget _mediaField(BuildContext context) {
    final mediaDirectory = MediaPickerScope.maybeOf(context);
    final mediaType = '${widgetConfig['type'] ?? ''}'.toLowerCase();
    final allowsAudio = mediaType == 'audio' || mediaType == 'sound';
    final allowsVideo = mediaType == 'video';
    final allowsImages = mediaType == 'image' || mediaType == 'media';
    if (mediaDirectory == null ||
        !(allowsAudio || allowsVideo || allowsImages)) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 260,
      child: TextFormField(
        initialValue: '${widgetConfig['media'] ?? ''}',
        decoration: InputDecoration(
          labelText: 'media',
          suffixIcon: IconButton(
            tooltip: 'Select media',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () async {
              final selected = await showMediaPicker(
                context,
                rootDirectory: mediaDirectory,
                allowAudio: allowsAudio,
                allowImages: allowsImages,
                allowVideo: allowsVideo,
              );
              if (selected != null) onChanged('media', selected);
            },
          ),
        ),
        onChanged: (value) => onChanged('media', value),
      ),
    );
  }

  Widget _field(
    String key,
    String value,
    void Function(String key, dynamic value) onChanged, {
    bool numeric = false,
  }) => SizedBox(
    width: key == 'text' ? 260 : 120,
    child: TextFormField(
      initialValue: value,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: key),
      onChanged: (next) =>
          onChanged(key, numeric ? num.tryParse(next) ?? 0 : next),
    ),
  );
}

class _CanonicalOverlayWidgetCard extends StatelessWidget {
  const _CanonicalOverlayWidgetCard({
    required this.index,
    required this.widgetConfig,
    required this.onChanged,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final JsonMap widgetConfig;
  final void Function(String key, dynamic value) onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final position = widgetConfig['position'] is Map
        ? Map<String, dynamic>.from(widgetConfig['position'] as Map)
        : const <String, dynamic>{};
    final size = widgetConfig['size'] is Map
        ? Map<String, dynamic>.from(widgetConfig['size'] as Map)
        : const <String, dynamic>{};
    final config = widgetConfig['config'] is Map
        ? Map<String, dynamic>.from(widgetConfig['config'] as Map)
        : const <String, dynamic>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Widget ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Move widget up',
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move widget down',
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Delete widget',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _textField('Name', '${widgetConfig['name'] ?? ''}', 'name'),
                _textField(
                  'Plugin',
                  '${widgetConfig['plugin'] ?? ''}',
                  'plugin',
                ),
                _textField(
                  'Widget',
                  '${widgetConfig['widget'] ?? ''}',
                  'widget',
                ),
                _numberField(
                  'X',
                  position['x'],
                  (value) => onChanged('position', {...position, 'x': value}),
                ),
                _numberField(
                  'Y',
                  position['y'],
                  (value) => onChanged('position', {...position, 'y': value}),
                ),
                _numberField(
                  'Width',
                  size['width'],
                  (value) => onChanged('size', {...size, 'width': value}),
                ),
                _numberField(
                  'Height',
                  size['height'],
                  (value) => onChanged('size', {...size, 'height': value}),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visible'),
              value: widgetConfig['visible'] != false,
              onChanged: (value) => onChanged('visible', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Locked'),
              value: widgetConfig['locked'] == true,
              onChanged: (value) => onChanged('locked', value),
            ),
            _OverlayWidgetConfigEditor(
              plugin: '${widgetConfig['plugin'] ?? ''}',
              widget: '${widgetConfig['widget'] ?? ''}',
              config: config,
              onChanged: (value) => onChanged('config', value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(String label, String value, String key) => SizedBox(
    width: 180,
    child: TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: (next) => onChanged(key, next),
    ),
  );

  Widget _numberField(String label, Object? value, ValueChanged<num> onValue) =>
      SizedBox(
        width: 110,
        child: TextFormField(
          initialValue: '${value ?? 0}',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          onChanged: (next) {
            final parsed = num.tryParse(next);
            if (parsed != null) onValue(parsed);
          },
        ),
      );
}

class _StreamPlanEditor extends StatefulWidget {
  const _StreamPlanEditor({
    required this.resource,
    required this.onSave,
    this.registryFuture,
    this.resourceOptionsLoader,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;
  final Future<DartPluginRegistry>? registryFuture;
  final GraphResourceOptionsLoader? resourceOptionsLoader;

  @override
  State<_StreamPlanEditor> createState() => _StreamPlanEditorState();
}

class _StreamPlanEditorState extends State<_StreamPlanEditor> {
  late final TextEditingController _name;
  late List<StreamPlanSegmentData> _segments;
  final Map<String, GlobalKey<_StreamPlanSegmentCardState>> _segmentKeys = {};
  ShowRunnerGraphEditor? _activationEditor;
  ShowRunnerGraphEditor? _deactivationEditor;

  @override
  void initState() {
    super.initState();
    final plan = StreamPlanData.fromConfig(widget.resource.config);
    _name = TextEditingController(text: plan.name);
    _segments = List<StreamPlanSegmentData>.of(plan.segments);
    if (widget.registryFuture != null) {
      _activationEditor = ShowRunnerGraphEditor(
        resourceOptionsLoader: widget.resourceOptionsLoader,
      )..loadAutomation(AutomationData.fromJson(plan.activationAutomation));
      _deactivationEditor = ShowRunnerGraphEditor(
        resourceOptionsLoader: widget.resourceOptionsLoader,
      )..loadAutomation(AutomationData.fromJson(plan.deactivationAutomation));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _activationEditor?.dispose();
    _deactivationEditor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit stream plan',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      if (_activationEditor != null)
        _inlineStreamPlanAutomation('On Activate', _activationEditor!),
      if (_deactivationEditor != null)
        _inlineStreamPlanAutomation('On Deactivate', _deactivationEditor!),
      if (_activationEditor == null)
        _automationSummary(
          'On Activate',
          widget.resource.config['activationAutomation'],
        ),
      if (_deactivationEditor == null)
        _automationSummary(
          'On Deactivate',
          widget.resource.config['deactivationAutomation'],
        ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Segments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add segment at start',
            onPressed: () => setState(() => _segments.insert(0, _newSegment())),
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: 'Add segment',
            onPressed: () => setState(() => _segments.add(_newSegment())),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      if (_segments.isEmpty)
        const Text('No segments defined.')
      else
        for (var index = 0; index < _segments.length; index++)
          _StreamPlanSegmentCard(
            key: _segmentKeys.putIfAbsent(
              _segments[index].id,
              GlobalKey<_StreamPlanSegmentCardState>.new,
            ),
            index: index,
            segment: _segments[index],
            registryFuture: widget.registryFuture,
            resourceOptionsLoader: widget.resourceOptionsLoader,
            onChanged: (segment) => setState(() => _segments[index] = segment),
            onMoveUp: index == 0
                ? null
                : () => setState(() {
                    final segment = _segments.removeAt(index);
                    _segments.insert(index - 1, segment);
                  }),
            onMoveDown: index == _segments.length - 1
                ? null
                : () => setState(() {
                    final segment = _segments.removeAt(index);
                    _segments.insert(index + 1, segment);
                  }),
            onDelete: () => setState(() {
              final removed = _segments.removeAt(index);
              _segmentKeys.remove(removed.id);
            }),
          ),
    ],
    onSave: () => widget.onSave(
      ResourceData(id: widget.resource.id, config: _savedConfig()),
    ),
  );

  JsonMap _savedConfig() {
    final plan = StreamPlanData.fromConfig(widget.resource.config);
    return {
      ...widget.resource.config,
      'name': _name.text.trim(),
      'activationAutomation':
          _activationEditor
              ?.toAutomation(AutomationData.fromJson(plan.activationAutomation))
              .toJson() ??
          plan.activationAutomation,
      'deactivationAutomation':
          _deactivationEditor
              ?.toAutomation(
                AutomationData.fromJson(plan.deactivationAutomation),
              )
              .toJson() ??
          plan.deactivationAutomation,
      'segments': _segments
          .map(
            (segment) =>
                (_segmentKeys[segment.id]?.currentState?._savedSegment() ??
                        segment)
                    .toJson(),
          )
          .toList(),
    };
  }

  StreamPlanSegmentData _newSegment() => StreamPlanSegmentData(
    id: 'segment-${DateTime.now().microsecondsSinceEpoch}',
    name: 'New segment',
    components: {
      'twitch-stream-info': {'title': '', 'category': ''},
    },
    activationAutomation: emptyInlineAutomation(),
    deactivationAutomation: emptyInlineAutomation(),
  );

  Widget _automationSummary(String label, Object? value) {
    final automation = value is Map
        ? Map<String, dynamic>.from(value)
        : emptyInlineAutomation();
    final graph = automation['graph'];
    final nodes = graph is Map && graph['nodes'] is List
        ? (graph['nodes'] as List).length
        : 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(label),
      subtitle: Text('$nodes automation node${nodes == 1 ? '' : 's'}'),
    );
  }

  Widget _inlineStreamPlanAutomation(
    String label,
    ShowRunnerGraphEditor editor,
  ) => ExpansionTile(
    key: ValueKey('stream-plan-$label'),
    leading: const Icon(Icons.account_tree_outlined),
    title: Text(label),
    subtitle: Text('${editor.controller.nodes.length} nodes'),
    children: [
      SizedBox(
        width: 720,
        child: ShowRunnerInlineGraphEditor(
          editor: editor,
          registryFuture: widget.registryFuture!,
        ),
      ),
    ],
  );
}

class _OverlayWidgetConfigEditor extends StatelessWidget {
  const _OverlayWidgetConfigEditor({
    required this.plugin,
    required this.widget,
    required this.config,
    required this.onChanged,
  });

  final String plugin;
  final String widget;
  final JsonMap config;
  final ValueChanged<JsonMap> onChanged;

  @override
  Widget build(BuildContext context) {
    final definition = findOverlayWidgetDefinition(plugin, widget);
    if (definition == null) {
      return TextFormField(
        initialValue: const JsonEncoder.withIndent('  ').convert(config),
        minLines: 4,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: 'Widget config (JSON object)',
          alignLabelWithHint: true,
        ),
        onChanged: (value) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map) onChanged(Map<String, dynamic>.from(decoded));
          } on FormatException {
            // Preserve the last valid config while the JSON is edited.
          }
        },
      );
    }
    return DartDataInput(
      schema: definition.configSchema,
      value: config,
      onChanged: (value) {
        if (value is Map) onChanged(Map<String, dynamic>.from(value));
      },
    );
  }
}

class _StreamPlanSegmentCard extends StatefulWidget {
  const _StreamPlanSegmentCard({
    super.key,
    required this.index,
    required this.segment,
    this.registryFuture,
    this.resourceOptionsLoader,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final int index;
  final StreamPlanSegmentData segment;
  final Future<DartPluginRegistry>? registryFuture;
  final GraphResourceOptionsLoader? resourceOptionsLoader;
  final ValueChanged<StreamPlanSegmentData> onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;

  @override
  State<_StreamPlanSegmentCard> createState() => _StreamPlanSegmentCardState();
}

class _StreamPlanSegmentCardState extends State<_StreamPlanSegmentCard> {
  ShowRunnerGraphEditor? _activationEditor;
  ShowRunnerGraphEditor? _deactivationEditor;

  @override
  void initState() {
    super.initState();
    if (widget.registryFuture != null) {
      _activationEditor =
          ShowRunnerGraphEditor(
            resourceOptionsLoader: widget.resourceOptionsLoader,
          )..loadAutomation(
            AutomationData.fromJson(widget.segment.activationAutomation),
          );
      _deactivationEditor =
          ShowRunnerGraphEditor(
            resourceOptionsLoader: widget.resourceOptionsLoader,
          )..loadAutomation(
            AutomationData.fromJson(widget.segment.deactivationAutomation),
          );
    }
  }

  @override
  void dispose() {
    _activationEditor?.dispose();
    _deactivationEditor?.dispose();
    super.dispose();
  }

  StreamPlanSegmentData _savedSegment() {
    final segment = widget.segment;
    return StreamPlanSegmentData(
      id: segment.id,
      name: segment.name,
      components: segment.components,
      activationAutomation:
          _activationEditor
              ?.toAutomation(
                AutomationData.fromJson(segment.activationAutomation),
              )
              .toJson() ??
          segment.activationAutomation,
      deactivationAutomation:
          _deactivationEditor
              ?.toAutomation(
                AutomationData.fromJson(segment.deactivationAutomation),
              )
              .toJson() ??
          segment.deactivationAutomation,
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Segment ${widget.index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Move up',
                onPressed: widget.onMoveUp,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: widget.onMoveDown,
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Delete segment',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            initialValue: widget.segment.name,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (name) => widget.onChanged(_copy(name: name)),
          ),
          const SizedBox(height: 8),
          if (_activationEditor != null)
            _inlineAutomation('On Activate', _activationEditor!),
          if (_deactivationEditor != null)
            _inlineAutomation('On Deactivate', _deactivationEditor!),
          if (_activationEditor == null)
            _automationSummary(
              'On Activate',
              widget.segment.activationAutomation,
            ),
          if (_deactivationEditor == null)
            _automationSummary(
              'On Deactivate',
              widget.segment.deactivationAutomation,
            ),
          const SizedBox(height: 8),
          _componentFields(),
        ],
      ),
    ),
  );

  Widget _componentFields() {
    final component = widget.segment.components['twitch-stream-info'];
    if (component is! Map) return const SizedBox.shrink();
    final config = Map<String, dynamic>.from(component);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _componentField(
          'Stream title',
          'title',
          config['title']?.toString() ?? '',
        ),
        _componentField(
          'Category',
          'category',
          config['category']?.toString() ?? '',
        ),
        _componentTagsField(
          config['tags'] is List
              ? (config['tags'] as List).map((tag) => tag.toString()).join(', ')
              : '',
        ),
      ],
    );
  }

  Widget _componentField(String label, String key, String value) => SizedBox(
    width: 260,
    child: TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: (next) {
        final components = {
          ...widget.segment.components,
          'twitch-stream-info': {
            ...Map<String, dynamic>.from(
              widget.segment.components['twitch-stream-info'] as Map,
            ),
            key: next,
          },
        };
        widget.onChanged(_copy(components: components));
      },
    ),
  );

  Widget _componentTagsField(String value) => SizedBox(
    width: 260,
    child: TextFormField(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Tags (comma separated)'),
      onChanged: (next) {
        final components = {
          ...widget.segment.components,
          'twitch-stream-info': {
            ...Map<String, dynamic>.from(
              widget.segment.components['twitch-stream-info'] as Map,
            ),
            'tags': next
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
          },
        };
        widget.onChanged(_copy(components: components));
      },
    ),
  );

  StreamPlanSegmentData _copy({String? name, JsonMap? components}) =>
      StreamPlanSegmentData(
        id: widget.segment.id,
        name: name ?? widget.segment.name,
        components: components ?? widget.segment.components,
        activationAutomation: widget.segment.activationAutomation,
        deactivationAutomation: widget.segment.deactivationAutomation,
      );

  Widget _automationSummary(String label, JsonMap automation) {
    final graph = automation['graph'];
    final nodes = graph is Map && graph['nodes'] is List
        ? (graph['nodes'] as List).length
        : 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(label),
      subtitle: Text('$nodes automation node${nodes == 1 ? '' : 's'}'),
    );
  }

  Widget _inlineAutomation(String label, ShowRunnerGraphEditor editor) =>
      ExpansionTile(
        key: ValueKey('stream-plan-segment-${widget.segment.id}-$label'),
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(label),
        subtitle: Text('${editor.controller.nodes.length} nodes'),
        children: [
          SizedBox(
            width: 720,
            child: ShowRunnerInlineGraphEditor(
              editor: editor,
              registryFuture: widget.registryFuture!,
            ),
          ),
        ],
      );
}

class _DashboardEditor extends StatefulWidget {
  const _DashboardEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_DashboardEditor> createState() => _DashboardEditorState();
}

class _DashboardEditorState extends State<_DashboardEditor> {
  late final TextEditingController _name;
  late final TextEditingController _remoteTwitchIds;
  late List<JsonMap> _pages;
  late List<JsonMap> _resourceSlots;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.resource.config['name']?.toString() ?? '',
    );
    _remoteTwitchIds = TextEditingController(
      text: _strings(widget.resource.config['remoteTwitchIds']).join(', '),
    );
    _pages = _maps(
      widget.resource.config['pages'],
    ).map(_dashboardPage).toList();
    _resourceSlots = _maps(widget.resource.config['resourceSlots']);
  }

  @override
  void dispose() {
    _name.dispose();
    _remoteTwitchIds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit dashboard',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _remoteTwitchIds,
        decoration: const InputDecoration(
          labelText: 'Shared Twitch viewer IDs',
          hintText: 'Comma-separated IDs; leave empty for private',
        ),
      ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Pages',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add page',
            onPressed: _addPage,
            icon: const Icon(Icons.post_add_outlined),
          ),
        ],
      ),
      if (_pages.isEmpty)
        const Text('No pages defined.')
      else
        for (var index = 0; index < _pages.length; index++) _page(index),
      const SizedBox(height: 16),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Resource slots',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add resource slot',
            onPressed: _addResourceSlot,
            icon: const Icon(Icons.add_link),
          ),
        ],
      ),
      if (_resourceSlots.isEmpty)
        const Text('No remote resource slots defined.')
      else
        for (var index = 0; index < _resourceSlots.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: TextFormField(
              initialValue:
                  '${_resourceSlots[index]['name'] ?? 'Unnamed slot'}',
              decoration: const InputDecoration(labelText: 'Slot name'),
              onChanged: (value) => _resourceSlots[index]['name'] = value,
            ),
            subtitle: Text(
              '${_resourceSlots[index]['slotType'] ?? 'unknown'} · ${_resourceSlots[index]['id'] ?? ''}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Move slot up',
                  onPressed: index == 0
                      ? null
                      : () => setState(
                          () => _moveListItem(_resourceSlots, index, index - 1),
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move slot down',
                  onPressed: index == _resourceSlots.length - 1
                      ? null
                      : () => setState(
                          () => _moveListItem(_resourceSlots, index, index + 1),
                        ),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Delete resource slot',
                  onPressed: () =>
                      setState(() => _resourceSlots.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'pages': _pages,
          'remoteTwitchIds': _remoteTwitchIds.text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(),
          'resourceSlots': _resourceSlots,
        },
      ),
    ),
  );

  Widget _page(int pageIndex) {
    final page = _pages[pageIndex];
    final sections = (page['sections'] as List).cast<JsonMap>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '${page['name'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'Page name'),
                    onChanged: (value) => page['name'] = value,
                  ),
                ),
                IconButton(
                  tooltip: 'Move page up',
                  onPressed: pageIndex == 0
                      ? null
                      : () => setState(
                          () => _moveListItem(_pages, pageIndex, pageIndex - 1),
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move page down',
                  onPressed: pageIndex == _pages.length - 1
                      ? null
                      : () => setState(
                          () => _moveListItem(_pages, pageIndex, pageIndex + 1),
                        ),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Delete page',
                  onPressed: () => setState(() => _pages.removeAt(pageIndex)),
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: 'Add section',
                  onPressed: () => setState(
                    () => sections.add({
                      'id': _newDashboardId('section'),
                      'name': 'New section',
                      'columns': 4,
                      'widgets': <JsonMap>[],
                    }),
                  ),
                  icon: const Icon(Icons.view_agenda_outlined),
                ),
              ],
            ),
            for (var index = 0; index < sections.length; index++)
              _section(sections, index),
          ],
        ),
      ),
    );
  }

  Widget _section(List<JsonMap> sections, int sectionIndex) {
    final section = sections[sectionIndex];
    final widgets = (section['widgets'] as List).cast<JsonMap>();
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '${section['name'] ?? ''}',
                  decoration: const InputDecoration(labelText: 'Section name'),
                  onChanged: (value) => section['name'] = value,
                ),
              ),
              DropdownButton<int>(
                value: (section['columns'] as num?)?.toInt() ?? 4,
                items: [
                  for (final columns in [1, 2, 3, 4, 6, 8, 12])
                    DropdownMenuItem(
                      value: columns,
                      child: Text('$columns columns'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => section['columns'] = value);
                },
              ),
              IconButton(
                tooltip: 'Move section up',
                onPressed: sectionIndex == 0
                    ? null
                    : () => setState(
                        () => _moveListItem(
                          sections,
                          sectionIndex,
                          sectionIndex - 1,
                        ),
                      ),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move section down',
                onPressed: sectionIndex == sections.length - 1
                    ? null
                    : () => setState(
                        () => _moveListItem(
                          sections,
                          sectionIndex,
                          sectionIndex + 1,
                        ),
                      ),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Delete section',
                onPressed: () =>
                    setState(() => sections.removeAt(sectionIndex)),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: 'Add widget',
                onPressed: () => _addWidget(widgets),
                icon: const Icon(Icons.widgets_outlined),
              ),
            ],
          ),
          for (var index = 0; index < widgets.length; index++)
            ListTile(
              dense: true,
              onTap: () => _editWidget(widgets, index),
              leading: const Icon(Icons.widgets_outlined),
              title: Text(_widgetTitle(widgets[index])),
              subtitle: Text(
                '${widgets[index]['plugin'] ?? 'unknown'} / ${widgets[index]['widget'] ?? widgets[index]['type'] ?? 'unknown'}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Move widget up',
                    onPressed: index == 0
                        ? null
                        : () => setState(
                            () => _moveListItem(widgets, index, index - 1),
                          ),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move widget down',
                    onPressed: index == widgets.length - 1
                        ? null
                        : () => setState(
                            () => _moveListItem(widgets, index, index + 1),
                          ),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: 'Delete widget',
                    onPressed: () => setState(() => widgets.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _addPage() => setState(
    () => _pages.add({
      'id': _newDashboardId('page'),
      'name': 'New page',
      'sections': <JsonMap>[],
    }),
  );

  Future<void> _editWidget(List<JsonMap> widgets, int index) async {
    final updated = await showDialog<JsonMap>(
      context: context,
      builder: (context) => _DashboardWidgetDialog(widget: widgets[index]),
    );
    if (updated != null && mounted) setState(() => widgets[index] = updated);
  }

  Future<void> _addResourceSlot() async {
    final slot = await showDialog<JsonMap>(
      context: context,
      builder: (context) => const _DashboardResourceSlotDialog(),
    );
    if (slot != null && mounted) setState(() => _resourceSlots.add(slot));
  }

  Future<void> _addWidget(List<JsonMap> widgets) async {
    final definition = await showDialog<DashboardWidgetDefinition>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add dashboard widget'),
        children: [
          for (final option in dashboardWidgetDefinitions)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.widgets_outlined),
                title: Text(option.name),
                subtitle: Text('${option.plugin}.${option.widget}'),
              ),
            ),
        ],
      ),
    );
    if (definition == null || !mounted) return;
    setState(
      () => widgets.add(definition.createWidget(id: _newDashboardId('widget'))),
    );
  }
}

class _DashboardWidgetDialog extends StatefulWidget {
  const _DashboardWidgetDialog({required this.widget});

  final JsonMap widget;

  @override
  State<_DashboardWidgetDialog> createState() => _DashboardWidgetDialogState();
}

class _DashboardWidgetDialogState extends State<_DashboardWidgetDialog> {
  late final TextEditingController _plugin;
  late final TextEditingController _widget;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _config;
  late JsonMap _configValue;
  String? _error;

  @override
  void initState() {
    super.initState();
    final size = widget.widget['size'] is Map
        ? Map<String, dynamic>.from(widget.widget['size'] as Map)
        : const <String, dynamic>{};
    _plugin = TextEditingController(
      text: widget.widget['plugin']?.toString() ?? 'dashboards',
    );
    _widget = TextEditingController(
      text: widget.widget['widget']?.toString() ?? 'label',
    );
    _width = TextEditingController(text: '${size['width'] ?? 4}');
    _height = TextEditingController(text: '${size['height'] ?? 1}');
    _configValue = widget.widget['config'] is Map
        ? Map<String, dynamic>.from(widget.widget['config'] as Map)
        : <String, dynamic>{};
    _config = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(_configValue),
    );
  }

  @override
  void dispose() {
    for (final controller in [_plugin, _widget, _width, _height, _config]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit dashboard widget'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _plugin,
              decoration: const InputDecoration(labelText: 'Plugin'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _widget,
              decoration: const InputDecoration(labelText: 'Widget'),
              onChanged: (_) => setState(() {}),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _width,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Width'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Height'),
                  ),
                ),
              ],
            ),
            _configEditor(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  void _save() {
    final definition = findDashboardWidgetDefinition(
      _plugin.text.trim(),
      _widget.text.trim(),
    );
    JsonMap config;
    if (definition != null) {
      config = _configValue;
    } else {
      dynamic decoded;
      try {
        decoded = jsonDecode(_config.text);
      } on FormatException {
        setState(() => _error = 'Widget config must be valid JSON.');
        return;
      }
      if (decoded is! Map) {
        setState(() => _error = 'Widget config must be a JSON object.');
        return;
      }
      config = Map<String, dynamic>.from(decoded);
    }
    Navigator.pop(context, {
      ...widget.widget,
      'plugin': _plugin.text.trim(),
      'widget': _widget.text.trim(),
      'size': {
        'width': int.tryParse(_width.text) ?? 4,
        'height': int.tryParse(_height.text) ?? 1,
      },
      'config': config,
    });
  }

  Widget _configEditor() {
    final definition = findDashboardWidgetDefinition(
      _plugin.text.trim(),
      _widget.text.trim(),
    );
    if (definition == null) {
      return TextField(
        controller: _config,
        maxLines: 8,
        decoration: const InputDecoration(labelText: 'Widget config JSON'),
      );
    }
    return DartDataInput(
      key: ValueKey('${definition.plugin}.${definition.widget}'),
      schema: definition.configSchema,
      value: _configValue,
      onChanged: (value) {
        if (value is Map) {
          setState(() => _configValue = Map<String, dynamic>.from(value));
        }
      },
    );
  }
}

class _DashboardResourceSlotDialog extends StatefulWidget {
  const _DashboardResourceSlotDialog();

  @override
  State<_DashboardResourceSlotDialog> createState() =>
      _DashboardResourceSlotDialogState();
}

class _DashboardResourceSlotDialogState
    extends State<_DashboardResourceSlotDialog> {
  final _name = TextEditingController();
  final _type = TextEditingController(text: 'SoundOutput');

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add resource slot'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _type,
          decoration: const InputDecoration(labelText: 'Slot type'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          final type = _type.text.trim();
          if (name.isEmpty || type.isEmpty) return;
          Navigator.pop(context, {
            'id': _newDashboardId('slot'),
            'name': name,
            'slotType': type,
            'config': <String, dynamic>{},
          });
        },
        child: const Text('Add'),
      ),
    ],
  );
}

class _VariableEditor extends StatefulWidget {
  const _VariableEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_VariableEditor> createState() => _VariableEditorState();
}

class _VariableEditorState extends State<_VariableEditor> {
  late final TextEditingController _name;
  late final TextEditingController _type;
  late final TextEditingController _defaultValue;
  late final TextEditingController _currentValue;
  late bool _persistent;

  @override
  void initState() {
    super.initState();
    final variable = VariableResource.fromResource(widget.resource);
    _name = TextEditingController(text: variable.name);
    _type = TextEditingController(text: variable.type);
    _defaultValue = TextEditingController(
      text: '${variable.defaultValue ?? ''}',
    );
    _currentValue = TextEditingController(
      text: '${variable.currentValue ?? ''}',
    );
    _persistent = variable.persistent;
  }

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _defaultValue.dispose();
    _currentValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit variable',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _type,
        decoration: const InputDecoration(labelText: 'Type'),
      ),
      TextField(
        controller: _defaultValue,
        decoration: const InputDecoration(labelText: 'Default value'),
      ),
      TextField(
        controller: _currentValue,
        decoration: const InputDecoration(labelText: 'Current value'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Persistent'),
        value: _persistent,
        onChanged: (value) => setState(() => _persistent = value),
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'type': _type.text.trim(),
          'defaultValue': _defaultValue.text,
          'persistent': _persistent,
        },
        state: {'value': _currentValue.text},
      ),
    ),
  );
}

class _ConnectionEditor extends StatefulWidget {
  const _ConnectionEditor({
    required this.title,
    required this.resource,
    required this.onSave,
    this.supportsLocal = false,
    this.testConnection,
  });

  final String title;
  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;
  final bool supportsLocal;
  final Future<bool> Function(String host, int port, String? password)?
  testConnection;

  @override
  State<_ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends State<_ConnectionEditor> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _password;
  late final TextEditingController _installPath;
  late bool _local;
  bool _testing = false;
  bool? _testSuccess;
  Object? _testError;

  @override
  void initState() {
    super.initState();
    final config = widget.resource.config;
    _name = TextEditingController(text: _displayValue(config['name']));
    _host = TextEditingController(text: _displayValue(config['host']));
    _port = TextEditingController(text: _displayValue(config['port']));
    _password = TextEditingController(text: _displayValue(config['password']));
    _installPath = TextEditingController(
      text: _displayValue(config['installPath']),
    );
    _local = config['local'] == true;
  }

  @override
  void dispose() {
    for (final controller in [_name, _host, _port, _password, _installPath]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _test() async {
    final tester = widget.testConnection;
    if (tester == null) return;
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null || port < 0 || port > 65535) {
      setState(() {
        _testSuccess = false;
        _testError = const FormatException('Enter a valid host and port.');
      });
      return;
    }
    setState(() {
      _testing = true;
      _testSuccess = null;
      _testError = null;
    });
    try {
      final success = await tester(host, port, _password.text);
      if (!mounted) return;
      setState(() => _testSuccess = success);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testError = error;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: widget.title,
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _host,
        decoration: const InputDecoration(labelText: 'Host'),
      ),
      TextField(
        controller: _port,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Port'),
      ),
      if (widget.testConnection != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'WebSocket Password',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _testSuccess == true
                          ? Icons.check
                          : _testSuccess == false
                          ? Icons.close
                          : Icons.wifi_find,
                    ),
              label: const Text('Test'),
            ),
          ],
        )
      else
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
      if (_testError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Connection test failed: $_testError',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        )
      else if (_testSuccess == true)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('OBS responded successfully.'),
        ),
      if (widget.supportsLocal) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Local OBS installation'),
          value: _local,
          onChanged: (value) => setState(() => _local = value),
        ),
        if (_local)
          TextField(
            controller: _installPath,
            decoration: const InputDecoration(labelText: 'Install path'),
          ),
      ],
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'host': _host.text.trim(),
          'port': int.tryParse(_port.text.trim()) ?? 4455,
          'password': _password.text,
          if (widget.supportsLocal) 'local': _local,
          if (widget.supportsLocal) 'installPath': _installPath.text.trim(),
        },
        state: widget.resource.state,
      ),
    ),
  );
}

Future<bool> _testObsConnection(String host, int port, String? password) async {
  final transport = ObsWebSocketTransport(
    host: host,
    port: port,
    password: password?.isEmpty == true ? null : password,
  );
  try {
    await transport.call('GetVersion', {});
    return true;
  } finally {
    await transport.close();
  }
}

class _TtsVoiceEditor extends StatefulWidget {
  const _TtsVoiceEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_TtsVoiceEditor> createState() => _TtsVoiceEditorState();
}

class _TtsVoiceEditorState extends State<_TtsVoiceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _providerConfig;
  late final TextEditingController _pitch;
  late final TextEditingController _rate;
  late String _provider;

  @override
  void initState() {
    super.initState();
    final config = widget.resource.config;
    _name = TextEditingController(text: _displayValue(config['name']));
    _provider = _displayValue(config['voiceProvider']);
    _providerConfig = TextEditingController(
      text: _jsonDisplayValue(config['providerConfig']),
    );
    final providerConfig = config['providerConfig'] is Map
        ? Map<String, dynamic>.from(config['providerConfig'] as Map)
        : const <String, dynamic>{};
    _pitch = TextEditingController(
      text: _displayValue(providerConfig['pitch'] ?? 0),
    );
    _rate = TextEditingController(
      text: _displayValue(providerConfig['rate'] ?? 0),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _providerConfig.dispose();
    _pitch.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit TTS voice',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TtsVoiceProviderPicker(
        value: _provider,
        onChanged: (value) => setState(() => _provider = value ?? ''),
      ),
      if (isSystemTtsProvider(_provider)) ...[
        TextField(
          controller: _pitch,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Pitch (-10 to 10)'),
        ),
        TextField(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rate (-10 to 10)'),
        ),
      ] else
        TextField(
          controller: _providerConfig,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Provider config (JSON object)',
          ),
        ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'voiceProvider': _provider,
          'providerConfig': isSystemTtsProvider(_provider)
              ? {
                  'pitch': num.tryParse(_pitch.text.trim()) ?? 0,
                  'rate': num.tryParse(_rate.text.trim()) ?? 0,
                }
              : _parseJsonMap(_providerConfig.text),
        },
        state: widget.resource.state,
      ),
    ),
  );
}

class _AudioSplitterEditor extends StatefulWidget {
  const _AudioSplitterEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_AudioSplitterEditor> createState() => _AudioSplitterEditorState();
}

class _AudioSplitterEditorState extends State<_AudioSplitterEditor> {
  late final TextEditingController _name;
  late List<JsonMap> _redirects;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: _displayValue(widget.resource.config['name']),
    );
    _redirects = _maps(
      widget.resource.config['redirects'],
    ).map(_audioSplit).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit audio splitter',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Audio outputs',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add audio output',
            onPressed: () => setState(() => _redirects.insert(0, _newSplit())),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      if (_redirects.isEmpty)
        const Text('No audio outputs defined.')
      else
        for (var index = 0; index < _redirects.length; index++)
          _AudioSplitCard(
            key: ValueKey(_redirects[index]['id']),
            index: index,
            split: _redirects[index],
            onChanged: (split) => setState(() => _redirects[index] = split),
            onDelete: () => setState(() => _redirects.removeAt(index)),
          ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'type': 'splitter',
          'redirects': [
            for (final redirect in _redirects) _savedAudioSplit(redirect),
          ],
        },
        state: widget.resource.state,
      ),
    ),
  );

  JsonMap _newSplit() => {
    'id': _audioSplitId(null),
    'mute': false,
    'volume': 100,
  };
}

JsonMap _savedAudioSplit(JsonMap split) {
  final saved = <String, dynamic>{...split};
  final output = saved['output']?.toString().trim();
  if (output == null || output.isEmpty) {
    saved.remove('output');
  } else {
    saved['output'] = output;
  }
  saved['id'] = _audioSplitId(saved['id']);
  saved['mute'] = saved['mute'] == true;
  saved['volume'] = ((saved['volume'] as num?)?.toDouble() ?? 100).clamp(
    0,
    100,
  );
  return saved;
}

class _AudioSplitCard extends StatelessWidget {
  const _AudioSplitCard({
    super.key,
    required this.index,
    required this.split,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final JsonMap split;
  final ValueChanged<JsonMap> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = split['mute'] == true;
    final volume = ((split['volume'] as num?)?.toDouble() ?? 100)
        .clamp(0, 100)
        .toDouble();
    return Card(
      color: muted ? Theme.of(context).colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Audio output ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Tooltip(
                  message: muted ? 'Unmute audio output' : 'Mute audio output',
                  child: Switch(
                    value: muted,
                    onChanged: (value) => onChanged({...split, 'mute': value}),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete audio output',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              key: ValueKey('audio-split-output-${split['id']}'),
              initialValue: split['output']?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Output resource ID',
              ),
              onChanged: (value) => onChanged({...split, 'output': value}),
            ),
            Row(
              children: [
                const SizedBox(width: 64, child: Text('Volume')),
                Expanded(
                  child: Slider(
                    value: volume,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${volume.round()}',
                    onChanged: (value) =>
                        onChanged({...split, 'volume': value}),
                  ),
                ),
                SizedBox(width: 42, child: Text('${volume.round()}%')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerGroupEditor extends StatefulWidget {
  const _ViewerGroupEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_ViewerGroupEditor> createState() => _ViewerGroupEditorState();
}

class _ViewerGroupEditorState extends State<_ViewerGroupEditor> {
  late final TextEditingController _name;
  late final TextEditingController _userId;
  late final Set<String> _userIds;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: _displayValue(widget.resource.config['name']),
    );
    _userId = TextEditingController();
    _userIds = {
      ...(widget.resource.config['userIds'] as List<dynamic>? ?? const []).map(
        (value) => value.toString(),
      ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _userId.dispose();
    super.dispose();
  }

  void _addUser() {
    final userId = _userId.text.trim();
    if (userId.isEmpty) return;
    setState(() {
      _userIds.add(userId);
      _userId.clear();
    });
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit Twitch viewer group',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _userId,
              decoration: const InputDecoration(labelText: 'Add user ID'),
            ),
          ),
          IconButton(
            onPressed: _addUser,
            tooltip: 'Add user',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final userId in _userIds)
            InputChip(
              label: Text(userId),
              onDeleted: () => setState(() => _userIds.remove(userId)),
            ),
        ],
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'userIds': _userIds.toList()..sort(),
        },
        state: widget.resource.state,
      ),
    ),
  );
}

class _ChannelPointRewardEditor extends StatefulWidget {
  const _ChannelPointRewardEditor({
    required this.resource,
    required this.onSave,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_ChannelPointRewardEditor> createState() =>
      _ChannelPointRewardEditorState();
}

class _ChannelPointRewardEditorState extends State<_ChannelPointRewardEditor> {
  late final TextEditingController _name;
  late final TextEditingController _twitchId;
  late final TextEditingController _prompt;
  late final TextEditingController _cost;
  late final TextEditingController _cooldown;
  late final TextEditingController _maxPerStream;
  late final TextEditingController _maxPerUser;
  late bool _controllable;
  late bool _transient;
  late bool _allowEnable;
  late bool _userInputRequired;
  late bool _skipQueue;
  late String _backgroundColor;

  Map<String, dynamic> get _configuredRewardData {
    final configured = widget.resource.config['rewardData'];
    final rewardData = configured is Map
        ? Map<String, dynamic>.from(configured)
        : <String, dynamic>{};
    // Older Flutter-created files briefly stored these fields at the root.
    // Read them as fallbacks so opening the editor is lossless for users.
    for (final key in [
      'prompt',
      'backgroundColor',
      'userInputRequired',
      'cost',
      'cooldown',
      'maxRedemptionsPerStream',
      'maxRedemptionsPerUserPerStream',
      'skipQueue',
    ]) {
      rewardData.putIfAbsent(key, () => widget.resource.config[key]);
    }
    return rewardData;
  }

  @override
  void initState() {
    super.initState();
    final config = widget.resource.config;
    final rewardData = _configuredRewardData;
    _name = TextEditingController(
      text: _displayValue(config['name'] ?? config['title']),
    );
    _twitchId = TextEditingController(text: _displayValue(config['twitchId']));
    _prompt = TextEditingController(text: _displayValue(rewardData['prompt']));
    _cost = TextEditingController(
      text: _displayValue(rewardData['cost'] ?? 100),
    );
    _cooldown = TextEditingController(
      text: _displayValue(rewardData['cooldown']),
    );
    _maxPerStream = TextEditingController(
      text: _displayValue(rewardData['maxRedemptionsPerStream']),
    );
    _maxPerUser = TextEditingController(
      text: _displayValue(rewardData['maxRedemptionsPerUserPerStream']),
    );
    _controllable = config['controllable'] != false;
    _transient = config['transient'] == true;
    _allowEnable = config['allowEnable'] != false;
    _userInputRequired = rewardData['userInputRequired'] == true;
    _skipQueue = rewardData['skipQueue'] == true;
    _backgroundColor = _displayValue(
      rewardData['backgroundColor'] ?? '#9147ff',
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _twitchId,
      _prompt,
      _cost,
      _cooldown,
      _maxPerStream,
      _maxPerUser,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit Twitch channel point reward',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _twitchId,
        decoration: const InputDecoration(
          labelText: 'Twitch reward ID',
          hintText: 'Leave empty until Twitch creates it',
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Controllable by ShowRunner'),
        subtitle: const Text(
          'When disabled, the reward is observed from Twitch but not managed by profiles.',
        ),
        value: _controllable,
        onChanged: (value) => setState(() => _controllable = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Allow enable/disable'),
        value: _allowEnable,
        onChanged: (value) => setState(() => _allowEnable = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Transient reward'),
        subtitle: const Text('Do not recreate it on Twitch when missing.'),
        value: _transient,
        onChanged: (value) => setState(() => _transient = value),
      ),
      TextField(
        controller: _prompt,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Prompt'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cost'),
            ),
          ),
          const SizedBox(width: 12),
          ColorValueField(
            label: 'Color',
            initialValue: _backgroundColor,
            onChanged: (value) => setState(() => _backgroundColor = value),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Require viewer input'),
        value: _userInputRequired,
        onChanged: (value) => setState(() => _userInputRequired = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Skip redemption queue'),
        value: _skipQueue,
        onChanged: (value) => setState(() => _skipQueue = value),
      ),
      TextField(
        controller: _cooldown,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Global cooldown (seconds)',
          hintText: 'Optional',
        ),
      ),
      TextField(
        controller: _maxPerStream,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Max redemptions per stream',
          hintText: 'Optional',
        ),
      ),
      TextField(
        controller: _maxPerUser,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Max redemptions per viewer per stream',
          hintText: 'Optional',
        ),
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'twitchId': _twitchId.text.trim(),
          'controllable': _controllable,
          'transient': _transient,
          'allowEnable': _allowEnable,
          'rewardData': {
            ..._configuredRewardData,
            'prompt': _prompt.text,
            'backgroundColor': _backgroundColor.trim(),
            'userInputRequired': _userInputRequired,
            'cost': (int.tryParse(_cost.text.trim()) ?? 1).clamp(1, 1000000),
            'cooldown': _optionalPositiveInt(_cooldown.text),
            'maxRedemptionsPerStream': _optionalPositiveInt(_maxPerStream.text),
            'maxRedemptionsPerUserPerStream': _optionalPositiveInt(
              _maxPerUser.text,
            ),
            'skipQueue': _skipQueue,
          },
        },
        state: widget.resource.state,
      ),
    ),
  );

  int? _optionalPositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    return parsed == null || parsed < 1 ? null : parsed;
  }
}

class _SpellcastEditor extends StatefulWidget {
  const _SpellcastEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_SpellcastEditor> createState() => _SpellcastEditorState();
}

class _SpellcastEditorState extends State<_SpellcastEditor> {
  static const _bitAmounts = <int>[
    10,
    20,
    30,
    40,
    50,
    100,
    150,
    200,
    250,
    300,
    350,
    400,
    450,
    500,
    550,
    600,
    650,
    700,
    750,
    800,
    850,
    900,
    950,
    1000,
    1050,
    1100,
    1150,
    1200,
    1250,
    1300,
    1350,
    1400,
    1450,
    1500,
    1550,
    1600,
    1650,
    1700,
    1750,
    1800,
    1850,
    1900,
    1950,
    2000,
  ];
  static const _colors = <String>[
    '#719ece',
    '#803FCC',
    '#CC3F9A',
    '#CCB23F',
    '#7ECC3F',
    '#CC4141',
    '#CC691E',
  ];

  late final TextEditingController _name;
  late final TextEditingController _spellId;
  late final TextEditingController _description;
  late bool _enabled;
  late int _bits;
  late String _color;

  Map<String, dynamic> get _spellData =>
      widget.resource.config['spellData'] is Map
      ? Map<String, dynamic>.from(widget.resource.config['spellData'] as Map)
      : <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final spellData = _spellData;
    _name = TextEditingController(
      text: _displayValue(widget.resource.config['name']),
    );
    _spellId = TextEditingController(
      text: _displayValue(widget.resource.config['spellId']),
    );
    _description = TextEditingController(
      text: _displayValue(spellData['description']),
    );
    _enabled = spellData['enabled'] == true;
    _bits = _nearestBitAmount((spellData['bits'] as num?)?.toInt() ?? 10);
    final configuredColor = spellData['color']?.toString();
    _color = _colors.contains(configuredColor)
        ? configuredColor!
        : _colors.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _spellId.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit Spellcast spell',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Title'),
      ),
      TextField(
        controller: _spellId,
        decoration: const InputDecoration(labelText: 'Spell ID'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enabled'),
        value: _enabled,
        onChanged: (value) => setState(() => _enabled = value),
      ),
      TextField(
        controller: _description,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Description'),
      ),
      DropdownButtonFormField<int>(
        initialValue: _bits,
        decoration: const InputDecoration(labelText: 'Bits'),
        items: [
          for (final amount in _bitAmounts)
            DropdownMenuItem(value: amount, child: Text('$amount bits')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _bits = value);
        },
      ),
      DropdownButtonFormField<String>(
        initialValue: _color,
        decoration: const InputDecoration(labelText: 'Color'),
        items: [
          for (final color in _colors)
            DropdownMenuItem(value: color, child: Text(color)),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _color = value);
        },
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'spellId': _spellId.text.trim(),
          'spellData': {
            ..._spellData,
            'enabled': _enabled,
            'description': _description.text,
            'bits': _bits,
            'color': _color,
          },
        },
        state: widget.resource.state,
      ),
    ),
  );

  int _nearestBitAmount(int value) => _bitAmounts.reduce(
    (left, right) =>
        (value - left).abs() <= (value - right).abs() ? left : right,
  );
}

class _ResourceForm extends StatelessWidget {
  const _ResourceForm({
    required this.title,
    required this.fields,
    required this.onSave,
  });

  final String title;
  final List<Widget> fields;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: fields),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () async {
          await onSave();
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _MapResourceEditor extends StatefulWidget {
  const _MapResourceEditor({
    required this.title,
    required this.resource,
    required this.fields,
    required this.onSave,
  });

  final String title;
  final ResourceData resource;
  final List<String> fields;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_MapResourceEditor> createState() => _MapResourceEditorState();
}

class _MapResourceEditorState extends State<_MapResourceEditor> {
  late final Map<String, dynamic> _values;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final field in widget.fields) field: widget.resource.config[field],
    };
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: widget.title,
    fields: [
      for (final field in widget.fields)
        DartDataInput(
          schema: _schemaFor(field),
          value: _values[field],
          onChanged: (value) => setState(() => _values[field] = value),
        ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {...widget.resource.config, ..._values},
        state: widget.resource.state,
      ),
    ),
  );

  DartDataInputSchema _schemaFor(String field) {
    final kind = switch (field) {
      'port' ||
      'cost' ||
      'numberOfLights' ||
      'ledCount' => DartDataInputKind.number,
      'local' ||
      'rgbAvailable' ||
      'kelvinAvailable' ||
      'dimmingAvailable' ||
      'transitionsAvailable' => DartDataInputKind.boolean,
      'userIds' => DartDataInputKind.array,
      'installPath' => DartDataInputKind.filePath,
      _ => DartDataInputKind.text,
    };
    return DartDataInputSchema(
      label: field,
      kind: kind,
      secret: field.toLowerCase().contains('password'),
    );
  }
}

String _displayValue(dynamic value) {
  if (value is List) return value.join(', ');
  return value?.toString() ?? '';
}

String _jsonDisplayValue(dynamic value) {
  if (value is Map) return jsonEncode(value);
  return _displayValue(value);
}

dynamic _parseJsonMap(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : trimmed;
  } on FormatException {
    return trimmed;
  }
}
