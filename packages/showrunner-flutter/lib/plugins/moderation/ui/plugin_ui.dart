import '../../registry/plugin_ui.dart';
import '../../registry/plugin_ui_contract.dart';
import '../runtime.dart';
import 'moderation_workspace.dart';

DartPluginUiContribution createModerationPluginUi(ModerationService service) =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          ModerationWorkspace(service: service),
    );
