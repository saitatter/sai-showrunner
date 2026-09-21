part of 'graph_workspace.dart';

class _StartupHealthBanner extends StatelessWidget {
  const _StartupHealthBanner({required this.healthFuture});

  final Future<StartupHealthSnapshot> healthFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StartupHealthSnapshot>(
      future: healthFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final state = result?.state ?? StartupHealthState.loading;
        final health = result?.health;
        final (label, color, icon) = switch (state) {
          StartupHealthState.loading => (
            'Checking local data',
            Colors.blueGrey,
            Icons.sync,
          ),
          StartupHealthState.ready => (
            'Local data ready',
            Colors.teal,
            Icons.check_circle,
          ),
          StartupHealthState.offline => (
            'Local data incomplete',
            Colors.orange,
            Icons.cloud_off,
          ),
          StartupHealthState.error => (
            'Local data error',
            Colors.redAccent,
            Icons.error_outline,
          ),
        };
        final details = health == null
            ? result?.error?.toString() ?? 'Waiting for the data service.'
            : '${health.settingsFileCount} settings files; '
                  '${health.stateDirectoryExists ? 'state directory found' : 'state directory missing'}';
        return Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(details, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      },
    );
  }
}

class _GraphStatus extends StatelessWidget {
  const _GraphStatus({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        editor.controller,
        editor.activeNodeIds,
        editor.executionStates,
        editor.graphFeedback,
      ]),
      builder: (context, child) {
        final states = editor.executionStates.value.values;
        final running = states
            .where((state) => state.status == GraphNodeExecutionStatus.running)
            .length;
        final completed = states
            .where((state) => state.status == GraphNodeExecutionStatus.success)
            .length;
        final failed = states
            .where((state) => state.status == GraphNodeExecutionStatus.error)
            .length;
        final feedback = editor.graphFeedback.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff182126).withValues(alpha: 0.94),
            border: Border.all(
              color: feedback == null
                  ? const Color(0xff2dd4bf)
                  : const Color(0xfff87171),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${editor.controller.nodes.length} nodes  /  '
                    '${editor.controller.project.projectData.links.length} links  '
                    '|  $running running  $completed done  $failed failed',
                    style: const TextStyle(
                      color: Color(0xffb8f3e8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (feedback != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.error_outline,
                            color: Color(0xfffca5a5),
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            feedback,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xfffecaca),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss graph feedback',
                          onPressed: () => editor.graphFeedback.value = null,
                          icon: const Icon(Icons.close, size: 15),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 22,
                            height: 22,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphWireHealthOverlay extends StatelessWidget {
  const _GraphWireHealthOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.nodeRevision,
      editor.activeGraphPath,
      editor.selectedInvalidFlowEdgeId,
      editor.selectedInvalidDataWireId,
    ]),
    builder: (context, child) {
      final invalidDataWires = editor.invalidDataWires;
      final invalidFlowEdges = editor.invalidFlowEdges;
      if (invalidDataWires.isEmpty && invalidFlowEdges.isEmpty) {
        return const SizedBox.shrink();
      }

      return Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (invalidDataWires.isNotEmpty)
                _wireHealthBanner(
                  context,
                  title:
                      '${invalidDataWires.length} invalid data wire'
                      '${invalidDataWires.length == 1 ? '' : 's'}',
                  message:
                      'One or more data connections could not be restored.',
                  onSelect: () =>
                      editor.selectInvalidDataWire(invalidDataWires.first.id),
                  onCleanup: () {
                    for (final wire in List.of(invalidDataWires)) {
                      editor.discardInvalidDataWire(wire.id);
                    }
                  },
                ),
              if (invalidDataWires.isNotEmpty && invalidFlowEdges.isNotEmpty)
                const SizedBox(height: 6),
              if (invalidFlowEdges.isNotEmpty)
                _wireHealthBanner(
                  context,
                  title:
                      '${invalidFlowEdges.length} invalid sequence edge'
                      '${invalidFlowEdges.length == 1 ? '' : 's'}',
                  message:
                      'One or more execution connections could not be restored.',
                  onSelect: () =>
                      editor.selectInvalidFlowEdge(invalidFlowEdges.first.id),
                  onCleanup: () {
                    for (final edge in List.of(invalidFlowEdges)) {
                      editor.discardInvalidFlowEdge(edge.id);
                    }
                  },
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _wireHealthBanner(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onSelect,
    required VoidCallback onCleanup,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xff4c292b).withValues(alpha: 0.96),
      border: Border.all(color: const Color(0xff9f4d50)),
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber, color: Color(0xffffb4a9), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xffffd7d2),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffffc4be),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onSelect, child: const Text('Select')),
          TextButton(onPressed: onCleanup, child: const Text('Clean up')),
        ],
      ),
    ),
  );
}

class _GraphHealth extends StatelessWidget {
  const _GraphHealth({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor.controller,
    builder: (context, child) {
      final issues = editor.currentGraphIssues();
      final healthy = issues.isEmpty;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff182126).withValues(alpha: 0.94),
          border: Border.all(
            color: healthy ? const Color(0xff4ade80) : const Color(0xfffbbf24),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: TextButton.icon(
          onPressed: () => _showGraphHealth(context, issues),
          icon: Icon(
            healthy ? Icons.check_circle_outline : Icons.warning_amber,
            color: healthy ? const Color(0xff86efac) : const Color(0xfffde68a),
            size: 16,
          ),
          label: Text(
            healthy
                ? 'Graph healthy'
                : '${issues.length} graph issue${issues.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: healthy
                  ? const Color(0xffbbf7d0)
                  : const Color(0xfffef3c7),
              fontSize: 12,
            ),
          ),
        ),
      );
    },
  );

  Future<void> _showGraphHealth(
    BuildContext context,
    List<String> issues,
  ) async {
    final invalidFlowEdges = editor.invalidFlowEdges;
    final invalidDataWires = editor.invalidDataWires;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Graph health'),
        content: SizedBox(
          width: 520,
          child:
              issues.isEmpty &&
                  invalidFlowEdges.isEmpty &&
                  invalidDataWires.isEmpty
              ? const Text('No structural issues were found.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final issue in issues)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber, size: 18),
                        title: Text(issue),
                      ),
                    if (invalidFlowEdges.isNotEmpty) ...[
                      const Divider(),
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.alt_route, size: 18),
                        title: Text('Stale flow links'),
                      ),
                      for (final edge in invalidFlowEdges)
                        ListTile(
                          dense: true,
                          title: Text(edge.id),
                          subtitle: Text(
                            '${edge.from} -> ${edge.to} '
                            '(${edge.port ?? 'completed'})',
                          ),
                          onTap: () {
                            editor.selectInvalidFlowEdge(edge.id);
                            Navigator.of(context).pop();
                          },
                          trailing: IconButton(
                            tooltip: 'Discard stale flow link',
                            onPressed: () {
                              editor.discardInvalidFlowEdge(edge.id);
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                    if (invalidDataWires.isNotEmpty) ...[
                      const Divider(),
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.data_object, size: 18),
                        title: Text('Stale data links'),
                      ),
                      for (final wire in invalidDataWires)
                        ListTile(
                          dense: true,
                          title: Text(wire.id),
                          subtitle: Text(
                            '${wire.fromNode}.${wire.fromPort} -> '
                            '${wire.toNode}.${wire.toPort}',
                          ),
                          onTap: () {
                            editor.selectInvalidDataWire(wire.id);
                            Navigator.of(context).pop();
                          },
                          trailing: IconButton(
                            tooltip: 'Discard stale data link',
                            onPressed: () {
                              editor.discardInvalidDataWire(wire.id);
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
        actions: [
          if (issues.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                editor.repairCurrentGraph();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Repair graph'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
