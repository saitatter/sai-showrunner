import 'package:flutter/widgets.dart';

import '../../services/showrunner_data_service.dart';
import '../runtime/provider_event_workers.dart';
import 'plugin_registry.dart';
import 'plugin_ui_contract.dart';

typedef DartPluginWorkspaceBuilder =
    Widget Function(
      BuildContext context,
      ShowRunnerDataService dataService,
      ProviderEventRuntime providerEvents,
      Future<DartPluginRegistry> registryFuture,
    );

final class DartFlutterPluginUiContribution
    implements DartPluginUiContribution {
  const DartFlutterPluginUiContribution({required this.builder});

  final DartPluginWorkspaceBuilder builder;

  @override
  Object build({
    required Object context,
    required Object dataService,
    required Object providerEvents,
    required Object registryFuture,
  }) => builder(
    context as BuildContext,
    dataService as ShowRunnerDataService,
    providerEvents as ProviderEventRuntime,
    registryFuture as Future<DartPluginRegistry>,
  );
}
