import '../../../features/resources/resource_editor_registry.dart';
import '../../../features/resources/resources_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createOverlaysPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => ResourcesWorkspace(
        dataService: host.dataService,
        editorRegistry: createDefaultResourceEditorRegistry(),
        registryFuture: host.registryFuture,
        resourceType: 'Overlay',
      ),
    );
