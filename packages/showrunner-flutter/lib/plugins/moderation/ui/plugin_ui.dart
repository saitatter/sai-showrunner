import '../../registry/plugin_ui.dart';
import '../runtime.dart';
import 'moderation_workspace.dart';

DartPluginUiContribution createModerationPluginUi(ModerationService service) =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => ModerationWorkspace(service: service),
    );
