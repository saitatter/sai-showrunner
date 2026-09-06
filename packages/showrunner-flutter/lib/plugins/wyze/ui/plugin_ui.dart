import '../../registry/plugin_ui.dart';
import 'wyze_workspace.dart';

DartPluginUiContribution createWyzePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          WyzeWorkspace(dataService: dataService),
    );
