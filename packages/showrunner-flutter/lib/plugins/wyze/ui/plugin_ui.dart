import '../../registry/plugin_ui.dart';
import '../../registry/plugin_ui_contract.dart';
import 'wyze_workspace.dart';

DartPluginUiContribution createWyzePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          WyzeWorkspace(dataService: dataService),
    );
