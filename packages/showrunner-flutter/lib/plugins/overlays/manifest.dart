import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';

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
        configSchema: _triggerWidgetSchema,
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
