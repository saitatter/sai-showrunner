import 'package:flutter/material.dart';

import 'automation_catalog_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildAutomationsWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => AutomationCatalogWorkspace(
  dataService: host.runtime.dataService,
  onOpen: host.automations.onOpenAutomation,
  onRepair: host.automations.onRepairAutomation,
  onCreate: host.automations.onCreateAutomation,
  onDelete: host.automations.onDeleteAutomation,
);
