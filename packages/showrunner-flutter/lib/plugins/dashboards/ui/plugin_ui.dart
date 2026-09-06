import '../../../features/resources/resource_editor_registry.dart';
import '../../../features/resources/resources_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createDashboardsPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          ResourcesWorkspace(
            dataService: dataService,
            editorRegistry: createDefaultResourceEditorRegistry(),
            registryFuture: registryFuture,
            resourceType: 'Dashboard',
          ),
    );
