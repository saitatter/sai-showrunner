import 'package:flutter/material.dart';

import 'automation_resource_workspace.dart';
import '../../features/resources/resource_options.dart';
import '../../features/support/support_workspaces.dart';

import '../../app/workspace_context.dart';

Widget buildGraphWorkspace(BuildContext context, WorkspaceHostContext host) =>
    host.graph.showGraphEditor
    ? AutomationResourceWorkspace(
        editor: host.graph.graphEditor,
        documents: host.graph.automationDocuments,
        onSelected: host.graph.onAutomationSelected,
        onClosed: host.graph.onAutomationClosed,
        onReordered: host.graph.onAutomationReordered,
        healthFuture: host.runtime.healthFuture,
        canvasKey: host.graph.graphCanvasKey,
        execution: host.graph.graphExecution,
        onRun: host.graph.onRunGraph,
        onRunNode: host.graph.onRunNode,
        resourceOptionsLoader: (type) =>
            loadResourceOptions(host.runtime.dataService, type),
      )
    : const LogsWorkspace();
