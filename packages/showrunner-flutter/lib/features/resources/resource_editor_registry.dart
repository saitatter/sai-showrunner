import 'dart:convert';
import 'package:flutter/material.dart';

import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../schema/stream_plan.dart';
import 'media_picker.dart';
import 'color_field.dart';
import '../../components/data_inputs/data_input.dart';
import '../../plugins/sound/ui/tts_voice_provider_picker.dart';

List<JsonMap> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <JsonMap>[];

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

final class DartResourceEditorDefinition {
  const DartResourceEditorDefinition({
    required this.pluginId,
    required this.resourceType,
    required this.displayName,
    required this.storageDirectory,
    required this.defaultConfig,
    required this.builder,
  });

  final String pluginId;
  final String resourceType;
  final String displayName;
  final String storageDirectory;
  final JsonMap Function(String name) defaultConfig;
  final DartResourceEditorBuilder builder;
}

final class DartResourceEditorRegistry {
  final _editors = <String, DartResourceEditorDefinition>{};

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
    _editors[definition.resourceType] = definition;
  }

  DartResourceEditorDefinition? find(String resourceType) =>
      _editors[resourceType];

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
        'width': 1920,
        'height': 1080,
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
      defaultConfig: (name) => {'name': name, 'spellId': ''},
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
      pluginId: 'twitch',
      resourceType: 'ChannelPointReward',
      displayName: 'Twitch Channel Point Reward',
      storageDirectory: 'twitch/channelpoints',
      defaultConfig: (name) => {
        'name': name,
        'twitchId': '',
        'title': name,
        'cost': 100,
      },
      fields: const ['name', 'twitchId', 'title', 'cost'],
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
    _ => _MapResourceEditor(
      title: 'Edit $displayName',
      resource: resource,
      fields: fields,
      onSave: onSave,
    ),
  },
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
  late List<JsonMap> _widgets;

  @override
  void initState() {
    super.initState();
    final overlay = OverlayResource.fromResource(widget.resource);
    _name = TextEditingController(text: overlay.name);
    _width = TextEditingController(text: '${overlay.width}');
    _height = TextEditingController(text: '${overlay.height}');
    _widgets = overlay.widgets
        .map((widget) => <String, dynamic>{...widget})
        .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
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
            onPressed: () => setState(
              () => _widgets.add({'type': 'text', 'text': 'New widget'}),
            ),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      if (_widgets.isEmpty)
        const Text('No widgets defined.')
      else
        for (var index = 0; index < _widgets.length; index++)
          _OverlayWidgetCard(
            index: index,
            widgetConfig: _widgets[index],
            onChanged: (key, value) =>
                setState(() => _widgets[index][key] = value),
            onDelete: () => setState(() => _widgets.removeAt(index)),
          ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'width': int.tryParse(_width.text) ?? 1920,
          'height': int.tryParse(_height.text) ?? 1080,
          'widgets': _widgets,
        },
      ),
    ),
  );
}

class _OverlayWidgetCard extends StatelessWidget {
  const _OverlayWidgetCard({
    required this.index,
    required this.widgetConfig,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final JsonMap widgetConfig;
  final void Function(String key, dynamic value) onChanged;
  final VoidCallback onDelete;

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

class _StreamPlanEditor extends StatefulWidget {
  const _StreamPlanEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_StreamPlanEditor> createState() => _StreamPlanEditorState();
}

class _StreamPlanEditorState extends State<_StreamPlanEditor> {
  late final TextEditingController _name;
  late List<StreamPlanSegmentData> _segments;

  @override
  void initState() {
    super.initState();
    final plan = StreamPlanData.fromConfig(widget.resource.config);
    _name = TextEditingController(text: plan.name);
    _segments = List<StreamPlanSegmentData>.of(plan.segments);
  }

  @override
  void dispose() {
    _name.dispose();
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
      _automationSummary(
        'On Activate',
        widget.resource.config['activationAutomation'],
      ),
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
            key: ValueKey(_segments[index].id),
            index: index,
            segment: _segments[index],
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
            onDelete: () => setState(() => _segments.removeAt(index)),
          ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'segments': _segments.map((segment) => segment.toJson()).toList(),
        },
      ),
    ),
  );

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
}

class _StreamPlanSegmentCard extends StatelessWidget {
  const _StreamPlanSegmentCard({
    super.key,
    required this.index,
    required this.segment,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final int index;
  final StreamPlanSegmentData segment;
  final ValueChanged<StreamPlanSegmentData> onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;

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
                  'Segment ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Move up',
                onPressed: onMoveUp,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: onMoveDown,
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Delete segment',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            initialValue: segment.name,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (name) => onChanged(_copy(name: name)),
          ),
          const SizedBox(height: 8),
          _componentFields(),
          const SizedBox(height: 4),
          Text(
            '${_nodeCount(segment.activationAutomation)} activation nodes · '
            '${_nodeCount(segment.deactivationAutomation)} deactivation nodes',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _componentFields() {
    final component = segment.components['twitch-stream-info'];
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
          ...segment.components,
          'twitch-stream-info': {
            ...Map<String, dynamic>.from(
              segment.components['twitch-stream-info'] as Map,
            ),
            key: next,
          },
        };
        onChanged(_copy(components: components));
      },
    ),
  );

  StreamPlanSegmentData _copy({String? name, JsonMap? components}) =>
      StreamPlanSegmentData(
        id: segment.id,
        name: name ?? segment.name,
        components: components ?? segment.components,
        activationAutomation: segment.activationAutomation,
        deactivationAutomation: segment.deactivationAutomation,
      );

  int _nodeCount(JsonMap automation) {
    final graph = automation['graph'];
    return graph is Map && graph['nodes'] is List
        ? (graph['nodes'] as List).length
        : 0;
  }
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
  late List<JsonMap> _pages;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.resource.config['name']?.toString() ?? '',
    );
    _pages = _maps(
      widget.resource.config['pages'],
    ).map(_dashboardPage).toList();
  }

  @override
  void dispose() {
    _name.dispose();
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
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'pages': _pages,
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
              IconButton(
                tooltip: 'Delete section',
                onPressed: () =>
                    setState(() => sections.removeAt(sectionIndex)),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: 'Add widget',
                onPressed: () => setState(
                  () => widgets.add({
                    'id': _newDashboardId('widget'),
                    'plugin': 'dashboards',
                    'widget': 'label',
                    'size': {'width': 4, 'height': 1},
                    'config': {'label': 'New widget', 'color': '#000000'},
                  }),
                ),
                icon: const Icon(Icons.widgets_outlined),
              ),
            ],
          ),
          for (var index = 0; index < widgets.length; index++)
            ListTile(
              dense: true,
              leading: const Icon(Icons.widgets_outlined),
              title: Text(
                '${widgets[index]['title'] ?? widgets[index]['type'] ?? 'Widget'}',
              ),
              subtitle: Text('Type: ${widgets[index]['type'] ?? 'unknown'}'),
              trailing: IconButton(
                tooltip: 'Delete widget',
                onPressed: () => setState(() => widgets.removeAt(index)),
                icon: const Icon(Icons.delete_outline),
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
  });

  final String title;
  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;
  final bool supportsLocal;

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
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
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
    _rate = TextEditingController(text: _displayValue(providerConfig['rate'] ?? 0));
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
    _redirects = _maps(widget.resource.config['redirects'])
        .map(_audioSplit)
        .toList();
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
            for (final redirect in _redirects)
              _savedAudioSplit(redirect),
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
                const SizedBox(
                  width: 64,
                  child: Text('Volume'),
                ),
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
      'port' || 'cost' => DartDataInputKind.number,
      'local' => DartDataInputKind.boolean,
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
