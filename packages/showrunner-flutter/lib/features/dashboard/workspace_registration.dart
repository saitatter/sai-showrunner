import 'package:flutter/material.dart';

import 'main_dashboard_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildHomeWorkspace(BuildContext context, WorkspaceHostContext host) =>
    MainDashboardWorkspace(
      dataService: host.runtime.dataService,
      actionQueue: host.runtime.actionQueue,
      providerEvents: host.runtime.providerEvents,
      registryFuture: host.runtime.pluginRegistryFuture,
      streamPlanRuntime: host.runtime.streamPlanRuntime,
      onOpenWorkspace: host.navigation.onDestinationSelected,
    );
