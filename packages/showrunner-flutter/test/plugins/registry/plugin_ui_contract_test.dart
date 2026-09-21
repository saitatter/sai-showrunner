import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/commands/app_command.dart';
import 'package:showrunner_flutter/app/workspace_registry.dart';
import 'package:showrunner_flutter/plugins/registry/flutter_plugin_ui_contract.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_module.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'exposes typed settings, resources, health, commands, and navigation',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-ui-host-');
      addTearDown(() => root.delete(recursive: true));
      final dataService = ShowRunnerDataService(root);
      final registry = DartPluginRegistry()
        ..registerModule(
          ManifestDartPluginModule(
            const DartPluginManifest(
              id: PluginId('test-plugin'),
              name: 'Test plugin',
              resources: [
                ResourceSpec(
                  ownerId: PluginId('test-plugin'),
                  resourceTypeId: ResourceTypeId('TestResource'),
                  displayName: 'Test resource',
                  storageDirectory: 'test/resources',
                  defaultConfigFactory: _defaultResource,
                ),
              ],
            ),
          ),
        );
      final eventHub = DartPluginEventHub();
      final providerEvents = ProviderEventRuntime(
        dataService: dataService,
        eventHub: eventHub,
      );
      addTearDown(eventHub.dispose);
      WorkspaceId? openedWorkspace;
      var commandRuns = 0;
      final host = DartPluginUiHostContext(
        dataService: dataService,
        providerEvents: providerEvents,
        registryFuture: Future.value(registry),
        commands: AppCommandRegistry([
          AppCommand(
            id: 'test.command',
            label: 'Test command',
            execute: (_) => commandRuns++,
          ),
        ]),
        onOpenWorkspace: (workspace) => openedWorkspace = workspace,
      );

      await host.saveSettings(const PluginId('test-plugin'), {'enabled': true});
      expect(await host.loadSettings(const PluginId('test-plugin')), {
        'enabled': true,
      });
      expect(await host.checkHealth(const PluginId('test-plugin')), isTrue);
      final repository = await host.resourceRepository(
        const ResourceTypeId('TestResource'),
      );
      expect(repository, isNotNull);
      expect(repository!.directory.path, endsWith('test/resources'));
      await host.runCommand('test.command');
      host.openWorkspace(WorkspaceIds.settings);
      expect(commandRuns, 1);
      expect(openedWorkspace, WorkspaceIds.settings);
    },
  );
}

Map<String, dynamic> _defaultResource(String name) => {'name': name};
