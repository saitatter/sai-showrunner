import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../app/commands/app_command.dart';
import '../../app/workspace_registry.dart';
import '../../persistence/resource_repository.dart';
import '../../schema/automation.dart';
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
    this.commands,
    this.onOpenWorkspace,
  });

  final ShowRunnerDataService dataService;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;
  final AppCommandRegistry? commands;
  final ValueChanged<WorkspaceId>? onOpenWorkspace;

  Future<JsonMap> loadSettings(PluginId pluginId) =>
      dataService.loadPluginSettings(pluginId.value);

  Future<void> saveSettings(PluginId pluginId, JsonMap values) =>
      dataService.savePluginSettings(pluginId.value, values);

  Future<bool> checkHealth(PluginId pluginId) =>
      registryFuture.then((registry) => registry.checkHealthId(pluginId));

  Future<ResourceRepository?> resourceRepository(
    ResourceTypeId resourceType,
  ) async {
    final contract = (await registryFuture).resource(resourceType);
    if (contract == null) return null;
    return ResourceRepository(
      Directory(
        '${dataService.userDirectory.path}/${contract.storageDirectory}',
      ),
      resourceType: resourceType.value,
      secretSettings: dataService.secretSettingsStore,
    );
  }

  Future<void> runCommand(String commandId, {BuildContext? context}) async {
    final commandRegistry = commands;
    if (commandRegistry == null) return;
    await commandRegistry.run(
      commandId,
      AppCommandContext(buildContext: context),
    );
  }

  void openWorkspace(WorkspaceId workspace) => onOpenWorkspace?.call(workspace);
}

abstract interface class DartPluginUiContribution {
  Widget build(BuildContext context, DartPluginUiHostContext host);
}
