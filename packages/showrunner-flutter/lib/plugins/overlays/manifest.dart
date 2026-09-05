import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createOverlaysPlugin({DartPluginEventHub? eventHub}) {
  final hub = eventHub ?? DartPluginEventHub();
  return DartPluginManifest(
    id: 'overlays',
    name: 'Overlays',
    actions: [
      DartActionDefinition(
        pluginId: 'overlays',
        actionId: 'triggerWidget',
        displayName: 'Trigger Overlay Widget',
        invoke: (config, context) => _triggerWidget(hub, config),
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
  eventHub.emit('overlayWidget', {
    'widgetId': widgetId,
    'overlayId': config['overlayId'],
    'payload': config['payload'],
  });
  return {'triggered': true, 'widgetId': widgetId};
}
