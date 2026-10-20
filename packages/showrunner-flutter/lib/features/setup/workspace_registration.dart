import 'package:flutter/material.dart';

import 'setup_workspace.dart';
import '../../app/workspace_registry.dart';

import '../../app/workspace_context.dart';

Widget buildSetupWorkspace(BuildContext context, WorkspaceHostContext host) =>
    SetupWorkspace(
      dataService: host.runtime.dataService,
      onOpenPlugin: (pluginId) {
        host.navigation.onPluginSelected?.call(pluginId);
        host.navigation.onDestinationSelected(WorkspaceIds.plugins);
      },
    );
