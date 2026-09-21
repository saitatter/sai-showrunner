import '../../registry/plugin_ui.dart';
import 'wyze_workspace.dart';

DartPluginUiContribution createWyzePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => WyzeWorkspace(dataService: host.dataService),
    );
