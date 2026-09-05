import 'dart:math';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../../schema/resource.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';

typedef OverlayResourceLoader =
    Future<ResourceData?> Function(String overlayId);
typedef OverlayResourceSaver = Future<void> Function(ResourceData resource);

final class OverlayResourceStore {
  const OverlayResourceStore({required this.load, required this.save});

  final OverlayResourceLoader load;
  final OverlayResourceSaver save;
}

abstract final class OverlayEventIds {
  static const widget = 'overlayWidget';
  static const widgetRpc = 'overlayWidgetRPC';
  static const broadcast = 'overlayBroadcast';
  static const configChanged = 'overlayConfigChanged';
}

const _triggerWidgetSchema = DartDataInputSchema(
  label: 'Overlay widget trigger',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Widget ID',
      key: 'widgetId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Overlay ID',
      key: 'overlayId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Payload',
      key: 'payload',
      kind: DartDataInputKind.object,
    ),
  ],
);

const _alertSchema = DartDataInputSchema(
  label: 'Overlay alert',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Alert widget',
      key: 'alert',
      kind: DartDataInputKind.object,
      required: true,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Title',
      key: 'title',
      kind: DartDataInputKind.multilineText,
      required: true,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Subtitle',
      key: 'subtitle',
      kind: DartDataInputKind.multilineText,
      required: true,
      defaultValue: '',
    ),
  ],
);

const _chatMessageSchema = DartDataInputSchema(
  label: 'Chat message',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Target widget',
      key: 'targetWidget',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Message ID',
      key: 'messageId',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Platform',
      key: 'platform',
      kind: DartDataInputKind.text,
      defaultValue: 'twitch',
    ),
    DartDataInputSchema(
      label: 'Viewer name',
      key: 'viewerName',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.multilineText,
      required: true,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Badges',
      key: 'badges',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
  ],
);

const _paidAlertSchema = DartDataInputSchema(
  label: 'Paid alert',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Target widget',
      key: 'targetWidget',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Event ID',
      key: 'eventId',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Platform',
      key: 'platform',
      kind: DartDataInputKind.text,
      defaultValue: 'youtube',
    ),
    DartDataInputSchema(
      label: 'Viewer name',
      key: 'viewerName',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Amount',
      key: 'amount',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Currency',
      key: 'currency',
      kind: DartDataInputKind.text,
      defaultValue: 'USD',
    ),
    DartDataInputSchema(
      label: 'Title',
      key: 'title',
      kind: DartDataInputKind.text,
      defaultValue: 'New Support',
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.multilineText,
      defaultValue: '',
    ),
  ],
);

const _beginSceneSchema = DartDataInputSchema(
  label: 'Begin scene overlay',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Target widget',
      key: 'targetWidget',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Scene key',
      key: 'sceneKey',
      kind: DartDataInputKind.text,
      defaultValue: 'main',
    ),
    DartDataInputSchema(
      label: 'Title',
      key: 'title',
      kind: DartDataInputKind.text,
      defaultValue: 'Starting Soon',
    ),
    DartDataInputSchema(
      label: 'Subtitle',
      key: 'subtitle',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Accent color',
      key: 'accentColor',
      kind: DartDataInputKind.color,
      defaultValue: '#9146ff',
    ),
  ],
);

const _endSceneSchema = DartDataInputSchema(
  label: 'End scene overlay',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Target widget',
      key: 'targetWidget',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Scene key',
      key: 'sceneKey',
      kind: DartDataInputKind.text,
      defaultValue: 'main',
    ),
  ],
);

const _emoteSchema = DartDataInputSchema(
  label: 'Emote message',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Bouncer widget',
      key: 'bouncer',
      kind: DartDataInputKind.object,
      required: true,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Emote message',
      key: 'message',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
  ],
);

const _visibilitySchema = DartDataInputSchema(
  label: 'Widget visibility',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Widget',
      key: 'widget',
      kind: DartDataInputKind.object,
      required: true,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Visibility',
      key: 'enabled',
      kind: DartDataInputKind.enumeration,
      options: ['true', 'false', 'toggle'],
      required: true,
      defaultValue: 'true',
    ),
  ],
);

DartPluginManifest createOverlaysPlugin({
  DartPluginEventHub? eventHub,
  OverlayResourceStore? overlayStore,
  Future<void> Function()? onDispose,
}) {
  final hub = eventHub ?? DartPluginEventHub();
  return DartPluginManifest(
    id: 'overlays',
    name: 'Overlays',
    dispose: onDispose,
    actions: [
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'triggerWidget',
        displayName: 'Trigger Overlay Widget',
        configSchema: _triggerWidgetSchema,
        invoke: (config, context) => _triggerWidget(hub, config),
      ),
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'alert',
        displayName: 'Show Alert',
        configSchema: _alertSchema,
        invoke: (config, context) =>
            _showAlert(hub, config, overlayStore: overlayStore),
      ),
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'pushChatMessage',
        displayName: 'Push Chat Message',
        configSchema: _chatMessageSchema,
        invoke: (config, context) => _pushChatMessage(hub, config),
      ),
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'pushPaidAlert',
        displayName: 'Push Paid Alert',
        configSchema: _paidAlertSchema,
        invoke: (config, context) => _pushPaidAlert(hub, config),
      ),
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'beginSceneOverlay',
        displayName: 'Begin Scene Overlay',
        configSchema: _beginSceneSchema,
        invoke: (config, context) => _sceneEvent(hub, 'scene.begin', config),
      ),
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'endSceneOverlay',
        displayName: 'End Scene Overlay',
        configSchema: _endSceneSchema,
        invoke: (config, context) => _sceneEvent(hub, 'scene.end', config),
      ),
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'spawnEmotes',
        displayName: 'Bounce Emotes',
        configSchema: _emoteSchema,
        invoke: (config, context) => _spawnEmotes(hub, config),
      ),
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'widgetVisibility',
        displayName: 'Widget Visibility',
        configSchema: _visibilitySchema,
        invoke: (config, context) =>
            _setWidgetVisibility(hub, config, overlayStore: overlayStore),
      ),
    ],
  );
}

Future<Object?> _triggerWidget(
  DartPluginEventHub eventHub,
  RuntimeMap config,
) async {
  final widgetId = config['widgetId']?.toString().trim() ?? '';
  if (widgetId.isEmpty) return {'triggered': false, 'widgetId': widgetId};
  eventHub.emit(OverlayEventIds.widget, {
    'widgetId': widgetId,
    'overlayId': config['overlayId'],
    'payload': config['payload'],
  });
  return {'triggered': true, 'widgetId': widgetId};
}

Future<Object?> _showAlert(
  DartPluginEventHub eventHub,
  RuntimeMap config, {
  required OverlayResourceStore? overlayStore,
}) async {
  final target = _target(config['alert']);
  if (target == null) return {'triggered': false};
  final mediaIndex = await _alertMediaIndex(target, overlayStore);
  if (mediaIndex == null) return {'triggered': false, ...target};
  eventHub.emit(OverlayEventIds.widgetRpc, {
    ...target,
    'rpcId': 'showAlert',
    'args': [
      config['title']?.toString() ?? '',
      config['subtitle']?.toString() ?? '',
      mediaIndex,
    ],
  });
  return {'triggered': true, ...target};
}

Future<Object?> _pushChatMessage(
  DartPluginEventHub eventHub,
  RuntimeMap config,
) async {
  final target = _target(config['targetWidget']);
  eventHub.emit(OverlayEventIds.broadcast, {
    'broadcastId': 'showrunner_chat_message',
    'payload': {
      'id': _eventId(config['messageId'], 'showrunner-chat'),
      'targetOverlayId': target?['overlayId'] ?? '',
      'targetWidgetId': target?['widgetId'] ?? '',
      'platform': _fallbackText(config['platform'], 'unknown'),
      'displayName': _fallbackText(config['viewerName'], 'unknown'),
      'username': _fallbackText(config['viewerName'], 'unknown'),
      'message': config['message']?.toString() ?? '',
      'badges': config['badges']?.toString() ?? '',
    },
  });
  return {'sent': true};
}

Future<Object?> _pushPaidAlert(
  DartPluginEventHub eventHub,
  RuntimeMap config,
) async {
  final target = _target(config['targetWidget']);
  eventHub.emit(OverlayEventIds.broadcast, {
    'broadcastId': 'showrunner_paid_alert',
    'payload': {
      'id': _eventId(config['eventId'], 'showrunner-paid'),
      'targetOverlayId': target?['overlayId'] ?? '',
      'targetWidgetId': target?['widgetId'] ?? '',
      'platform': _fallbackText(config['platform'], 'unknown'),
      'displayName': _fallbackText(config['viewerName'], 'unknown'),
      'amount': config['amount']?.toString() ?? '',
      'currency': _fallbackText(config['currency'], ''),
      'title': _fallbackText(config['title'], 'New Support'),
      'message': config['message']?.toString() ?? '',
    },
  });
  return {'sent': true};
}

Future<Object?> _sceneEvent(
  DartPluginEventHub eventHub,
  String type,
  RuntimeMap config,
) async {
  final target = _target(config['targetWidget']);
  eventHub.emit(OverlayEventIds.broadcast, {
    'broadcastId': 'showrunner_scene_event',
    'payload': {
      'type': type,
      'targetOverlayId': target?['overlayId'] ?? '',
      'targetWidgetId': target?['widgetId'] ?? '',
      'sceneKey': _fallbackText(config['sceneKey'], 'main'),
      'title': config['title']?.toString() ?? '',
      'subtitle': config['subtitle']?.toString() ?? '',
      'accentColor': _fallbackText(config['accentColor'], '#9146ff'),
    },
  });
  return {'sent': true, 'type': type};
}

Future<Object?> _spawnEmotes(
  DartPluginEventHub eventHub,
  RuntimeMap config,
) async {
  final target = _target(config['bouncer']);
  if (target == null) return {'triggered': false};
  eventHub.emit(OverlayEventIds.widgetRpc, {
    ...target,
    'rpcId': 'spawnEmotes',
    'args': [config['message']?.toString() ?? ''],
  });
  return {'triggered': true, ...target};
}

Future<Object?> _setWidgetVisibility(
  DartPluginEventHub eventHub,
  RuntimeMap config, {
  required OverlayResourceStore? overlayStore,
}) async {
  if (overlayStore == null) {
    throw StateError('Overlay resource storage is not configured.');
  }
  final target = _target(config['widget']);
  if (target == null) return {'widgetVisible': false};
  final overlayId = target['overlayId']!;
  final widgetId = target['widgetId']!;
  final resource = await overlayStore.load(overlayId);
  if (resource == null) return {'widgetVisible': false};
  final widgets = _maps(resource.config['widgets']);
  final index = widgets.indexWhere(
    (widget) => widget['id']?.toString() == widgetId,
  );
  if (index < 0) return {'widgetVisible': false};
  final current = widgets[index]['visible'] == true;
  final requested = config['enabled'];
  final visible = requested?.toString() == 'toggle'
      ? !current
      : requested == true || requested?.toString() == 'true';
  widgets[index] = {...widgets[index], 'visible': visible};
  await overlayStore.save(
    ResourceData(
      id: resource.id,
      config: {...resource.config, 'widgets': widgets},
      state: resource.state,
    ),
  );
  eventHub.emit(OverlayEventIds.configChanged, {
    'overlayId': overlayId,
    'widgetId': widgetId,
    'visible': visible,
  });
  return {'widgetVisible': visible};
}

Future<int?> _alertMediaIndex(
  Map<String, String> target,
  OverlayResourceStore? overlayStore,
) async {
  if (overlayStore == null) return 0;
  final resource = await overlayStore.load(target['overlayId']!);
  if (resource == null) return null;
  final widget = _maps(
    resource.config['widgets'],
  ).where((item) => item['id']?.toString() == target['widgetId']).firstOrNull;
  final widgetConfig = widget?['config'];
  final media = widgetConfig is Map ? _maps(widgetConfig['media']) : const [];
  if (media.isEmpty) return null;
  final weights = media
      .map((item) => _number(item['weight'], 0))
      .map((weight) => max(weight, 0))
      .toList();
  final total = weights.fold<double>(0, (sum, weight) => sum + weight);
  if (total <= 0) return 0;
  var targetWeight = Random().nextDouble() * total;
  for (var index = 0; index < weights.length; index++) {
    targetWeight -= weights[index];
    if (targetWeight <= 0) return index;
  }
  return weights.length - 1;
}

Map<String, String>? _target(Object? value) {
  if (value is! Map) return null;
  final widgetId = value['widgetId']?.toString().trim() ?? '';
  final overlayId = value['overlayId']?.toString().trim() ?? '';
  if (widgetId.isEmpty || overlayId.isEmpty) return null;
  return {'widgetId': widgetId, 'overlayId': overlayId};
}

String _fallbackText(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _eventId(Object? value, String prefix) =>
    _fallbackText(value, '$prefix-${DateTime.now().microsecondsSinceEpoch}');

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

List<RuntimeMap> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <RuntimeMap>[];
