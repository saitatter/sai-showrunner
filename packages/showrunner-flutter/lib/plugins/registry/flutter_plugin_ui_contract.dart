import 'package:flutter/widgets.dart';

import '../../services/showrunner_data_service.dart';
import '../runtime/provider_event_workers.dart';
import 'plugin_registry.dart';

/// Typed dependencies made available to a Flutter plugin workspace.
///
/// This is deliberately outside [DartPluginManifest]. The manifest remains a
/// declarative contract that can be inspected without constructing widgets or
/// reaching into Flutter-specific services.
final class DartPluginUiHostContext {
  const DartPluginUiHostContext({
    required this.dataService,
    required this.providerEvents,
    required this.registryFuture,
  });

  final ShowRunnerDataService dataService;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;
}

abstract interface class DartPluginUiContribution {
  Widget build(BuildContext context, DartPluginUiHostContext host);
}
