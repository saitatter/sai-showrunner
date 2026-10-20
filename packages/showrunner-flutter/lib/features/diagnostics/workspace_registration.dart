import 'package:flutter/material.dart';

import 'diagnostics_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildDiagnosticsWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => DiagnosticsWorkspace(
  healthFuture: host.runtime.healthFuture,
  queue: host.runtime.actionQueue,
  providerEvents: host.runtime.providerEvents,
  registryFuture: host.runtime.pluginRegistryFuture,
);
