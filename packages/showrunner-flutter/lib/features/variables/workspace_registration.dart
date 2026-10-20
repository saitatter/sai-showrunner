import 'package:flutter/material.dart';

import 'variables_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildVariablesWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => VariablesWorkspace(
  dataService: host.runtime.dataService,
  eventHub: host.runtime.providerEvents.eventHub,
  variableRuntime: host.runtime.variableRuntime,
);

Widget buildViewerVariablesWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => VariablesWorkspace(
  dataService: host.runtime.dataService,
  eventHub: host.runtime.providerEvents.eventHub,
  variableRuntime: host.runtime.variableRuntime,
  initialSection: VariablesWorkspaceSection.viewerVariables,
);
