import 'package:flutter/widgets.dart';

import '../../services/showrunner_data_service.dart';
import '../runtime/provider_event_workers.dart';
import 'plugin_registry.dart';
import 'flutter_plugin_ui_contract.dart';

export 'flutter_plugin_ui_contract.dart';

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
  Widget build(BuildContext context, DartPluginUiHostContext host) => builder(
    context,
    host.dataService,
    host.providerEvents,
    host.registryFuture,
  );
}
