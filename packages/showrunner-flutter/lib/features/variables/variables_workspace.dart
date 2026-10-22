import 'package:flutter/material.dart';
import '../../services/showrunner_data_service.dart';
import '../../services/plugin_event_hub.dart';
import '../../plugins/variables/runtime.dart';
import 'global_variables_panel.dart';
import 'viewer_data_workspace_panel.dart';
export 'viewer_data_workspace_panel.dart' show ViewerDataWorkspacePanel;

enum VariablesWorkspaceSection { variables, viewerVariables }

/// Global catalog and viewer queries have independent presentation/async owners.
class VariablesWorkspace extends StatelessWidget {
  const VariablesWorkspace({
    super.key,
    required this.dataService,
    this.eventHub,
    this.variableRuntime,
    this.initialSection = VariablesWorkspaceSection.variables,
  });
  final ShowRunnerDataService dataService;
  final DartPluginEventHub? eventHub;
  final DartVariableRuntime? variableRuntime;
  final VariablesWorkspaceSection initialSection;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (initialSection == VariablesWorkspaceSection.viewerVariables) ...[
        Text(
          'Viewer Variables',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Define and inspect per-viewer values used by Twitch automation.',
        ),
        const SizedBox(height: 16),
      ] else ...[
        GlobalVariablesPanel(
          dataService: dataService,
          variableRuntime: variableRuntime,
        ),
        const SizedBox(height: 24),
      ],
      ViewerDataWorkspacePanel(
        repository: dataService.storage.viewerData,
        eventHub: eventHub,
      ),
    ],
  );
}
