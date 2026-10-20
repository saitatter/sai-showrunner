import 'package:flutter/material.dart';

import 'plugin_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildPluginsWorkspace(BuildContext context, WorkspaceHostContext host) =>
    PluginWorkspace(
      dataService: host.runtime.dataService,
      registryFuture: host.runtime.pluginRegistryFuture,
      providerEvents: host.runtime.providerEvents,
      selectedPluginId: host.navigation.selectedPluginId,
      commands: host.commands,
      onOpenWorkspace: host.navigation.onDestinationSelected,
    );
