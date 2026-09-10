import '../../registry/plugin_ui.dart';
import '../services/heart_rate_service.dart';
import 'heart_rate_workspace.dart';

DartPluginUiContribution createHeartRatePluginUi(HeartRateService service) =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          HeartRateWorkspace(service: service),
    );
