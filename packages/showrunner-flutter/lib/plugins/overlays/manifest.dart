import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createOverlaysPlugin() => const DartPluginManifest(
  id: 'overlays',
  name: 'Overlays',
  actions: [
    DartActionDefinition(
      pluginId: 'overlays',
      actionId: 'triggerWidget',
      displayName: 'Trigger Overlay Widget',
      invoke: _triggerWidget,
    ),
  ],
);

Future<Object?> _triggerWidget(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final widgetId = config['widgetId']?.toString() ?? '';
  return {'triggered': widgetId.isNotEmpty, 'widgetId': widgetId};
}
