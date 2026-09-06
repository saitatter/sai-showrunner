import 'package:flutter/material.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../services/showrunner_data_service.dart';
import '../resources/resource_editor_registry.dart';
import '../resources/resources_workspace.dart';
import 'plugin_workspace.dart';

/// Keeps the complete generic contract surface available while giving
/// resource-backed integrations a first-class resource tab.
final class ResourceBackedPluginWorkspace extends StatelessWidget {
  const ResourceBackedPluginWorkspace({
    super.key,
    required this.pluginId,
    this.resourceType,
    this.resourceTypes,
    required this.dataService,
    required this.registryFuture,
    required this.providerEvents,
  });

  final String pluginId;
  final String? resourceType;
  final Set<String>? resourceTypes;
  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final ProviderEventRuntime providerEvents;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Integration', icon: Icon(Icons.extension_outlined)),
            Tab(text: 'Resources', icon: Icon(Icons.folder_open_outlined)),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              PluginWorkspace(
                dataService: dataService,
                registryFuture: registryFuture,
                providerEvents: providerEvents,
                selectedPluginId: pluginId,
                forceGenericDetails: true,
              ),
              ResourcesWorkspace(
                dataService: dataService,
                editorRegistry: createDefaultResourceEditorRegistry(),
                registryFuture: registryFuture,
                resourceType: resourceType,
                resourceTypes: resourceTypes,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
