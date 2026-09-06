import '../../features/plugins/plugin_workspace.dart';
import 'plugin_ui.dart';
import 'plugin_ui_contract.dart';

/// Exposes the canonical integration details surface for plugins whose
/// original renderer only contributed icons or input registrations.
///
/// Keeping this as a real UI contribution makes the plugin boundary explicit
/// without duplicating an otherwise identical settings/actions/triggers page.
DartPluginUiContribution createGenericPluginUi(String pluginId) =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          PluginWorkspace(
            dataService: dataService,
            registryFuture: registryFuture,
            providerEvents: providerEvents,
            selectedPluginId: pluginId,
          ),
    );
