import 'dart:async';
import '../../persistence/viewer_data_repository.dart';
import '../../persistence/sqlite_viewer_data_repository.dart';
import '../../services/structured_logger.dart';
import 'package:flutter/material.dart';
import '../../services/showrunner_data_service.dart';
import '../../services/plugin_event_hub.dart';
import '../../plugins/variables/runtime.dart';
import 'global_variables_panel.dart';
import 'viewer_data_workspace_panel.dart';
export 'viewer_data_workspace_panel.dart' show ViewerDataWorkspacePanel;

enum VariablesWorkspaceSection { variables, viewerVariables }

/// Global catalog and viewer queries have independent presentation/async owners.
class VariablesWorkspace extends StatefulWidget {
  const VariablesWorkspace({
    super.key,
    required this.dataService,
    this.eventHub,
    this.viewerDataRepository,
    this.variableRuntime,
    this.initialSection = VariablesWorkspaceSection.variables,
  });
  final ShowRunnerDataService dataService;
  final ViewerDataRepository? viewerDataRepository;
  final DartPluginEventHub? eventHub;
  final DartVariableRuntime? variableRuntime;
  final VariablesWorkspaceSection initialSection;
  @override
  State<VariablesWorkspace> createState() => _VariablesWorkspaceState();
}

class _VariablesWorkspaceState extends State<VariablesWorkspace> {
  late ViewerDataRepository _repository;
  bool _ownsRepository = false;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _ownsRepository = widget.viewerDataRepository == null;
    _repository =
        widget.viewerDataRepository ?? widget.dataService.storage.viewerData;
  }

  void _release() {
    final repository = _repository;
    if (_ownsRepository && repository is SqliteViewerDataRepository) {
      unawaited(
        repository.close().catchError((Object _) {
          ShowRunnerLogger.instance.warning(
            'persistence',
            'Viewer database close failed.',
          );
        }),
      );
    }
  }

  @override
  void didUpdateWidget(VariablesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerDataRepository != widget.viewerDataRepository ||
        oldWidget.dataService.userDirectory.path !=
            widget.dataService.userDirectory.path) {
      _release();
      _bind();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (widget.initialSection ==
          VariablesWorkspaceSection.viewerVariables) ...[
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
          dataService: widget.dataService,
          variableRuntime: widget.variableRuntime,
        ),
        const SizedBox(height: 24),
      ],
      ViewerDataWorkspacePanel(
        repository: _repository,
        eventHub: widget.eventHub,
      ),
    ],
  );
}
