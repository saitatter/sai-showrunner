import 'dart:convert';

import 'package:flutter/material.dart';

import '../../editor/showrunner_graph_editor.dart';
import '../../runtime/execution_trace.dart';

/// Compact execution history for the currently open automation.
///
/// The panel is intentionally driven by the trace service rather than by the
/// graph editor's node map. This keeps concurrent runs distinguishable and
/// lets the editor pin one retained run without changing runtime execution.
class GraphExecutionPanel extends StatefulWidget {
  const GraphExecutionPanel({super.key, required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  State<GraphExecutionPanel> createState() => _GraphExecutionPanelState();
}

class _GraphExecutionPanelState extends State<GraphExecutionPanel> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.editor.executionTraceService;
    final source = widget.editor.executionTraceSource;
    if (service == null || source == null) return const SizedBox.shrink();

    return StreamBuilder<ExecutionTraceEvent>(
      stream: service.events,
      builder: (context, snapshot) {
        final runs = [...service.snapshotsFor(source)]
          ..sort(
            (left, right) =>
                right.info.startedAt.compareTo(left.info.startedAt),
          );
        if (runs.isEmpty) return const SizedBox.shrink();
        final activeCount = runs
            .where((run) => run.info.status == ExecutionTraceRunStatus.running)
            .length;
        final pinned = widget.editor.pinnedExecutionId;
        final pinnedRun = pinned == null
            ? null
            : runs
                  .where((run) => run.info.executionId == pinned)
                  .toList()
                  .firstOrNull;

        return Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ExecutionPanelHeader(
                  activeCount: activeCount,
                  pinned: pinned != null,
                  collapsed: _collapsed,
                  onToggle: () => setState(() => _collapsed = !_collapsed),
                  onLive: pinned == null
                      ? null
                      : () => widget.editor.pinExecution(null),
                ),
                if (!_collapsed)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 156,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          scrollDirection: Axis.horizontal,
                          itemCount: runs.length,
                          itemBuilder: (context, index) {
                            final run = runs[index];
                            return _ExecutionRunCard(
                              run: run,
                              pinned: run.info.executionId == pinned,
                              onTap: () => widget.editor.pinExecution(
                                run.info.executionId,
                              ),
                            );
                          },
                        ),
                      ),
                      if (pinnedRun != null)
                        _ExecutionRunInspector(
                          run: pinnedRun,
                          editor: widget.editor,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExecutionPanelHeader extends StatelessWidget {
  const _ExecutionPanelHeader({
    required this.activeCount,
    required this.pinned,
    required this.collapsed,
    required this.onToggle,
    required this.onLive,
  });

  final int activeCount;
  final bool pinned;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onLive;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: Row(
      children: [
        const SizedBox(width: 12),
        Text(
          'EXECUTIONS',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 10),
        if (activeCount > 0)
          _ExecutionBadge(
            label: '$activeCount live',
            color: const Color(0xff65d6a0),
          ),
        if (pinned) ...[
          const SizedBox(width: 6),
          _ExecutionBadge(
            label: 'pinned',
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
        const Spacer(),
        if (onLive != null)
          TextButton(
            onPressed: onLive,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Live'),
          ),
        IconButton(
          onPressed: onToggle,
          tooltip: collapsed ? 'Expand executions' : 'Collapse executions',
          icon: Icon(collapsed ? Icons.expand_less : Icons.expand_more),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}

class _ExecutionRunCard extends StatelessWidget {
  const _ExecutionRunCard({
    required this.run,
    required this.pinned,
    required this.onTap,
  });

  final ExecutionTraceRunSnapshot run;
  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = run.info;
    final color = _executionStatusColor(info.status);
    final duration = info.duration ?? DateTime.now().difference(info.startedAt);
    final shortId = info.executionId.length > 12
        ? info.executionId.substring(info.executionId.length - 8)
        : info.executionId;

    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 2),
      child: SizedBox(
        width: 188,
        child: Material(
          color: pinned
              ? color.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: pinned ? color : Theme.of(context).dividerColor,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _executionStatusIcon(info.status),
                        size: 15,
                        color: color,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '#$shortId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        info.mode.name,
                        style: TextStyle(color: color, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _executionStatusLabel(info.status),
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                  if (info.source.queueId != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Queue: ${info.source.queueName ?? info.source.queueId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${duration.inMilliseconds} ms',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExecutionBadge extends StatelessWidget {
  const _ExecutionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _ExecutionRunInspector extends StatelessWidget {
  const _ExecutionRunInspector({required this.run, required this.editor});

  final ExecutionTraceRunSnapshot run;
  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) {
    final info = run.info;
    final nodes = run.nodes.values.toList()
      ..sort((left, right) {
        final leftStarted = left.startedAt;
        final rightStarted = right.startedAt;
        if (leftStarted == null && rightStarted == null) return 0;
        if (leftStarted == null) return 1;
        if (rightStarted == null) return -1;
        return leftStarted.compareTo(rightStarted);
      });
    final color = _executionStatusColor(info.status);

    return Container(
      height: 186,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 230,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _executionStatusIcon(info.status),
                        size: 16,
                        color: color,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _executionStatusLabel(info.status),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InspectorMetaLine(label: 'Run', value: info.executionId),
                  _InspectorMetaLine(
                    label: 'Source',
                    value: info.source.toString(),
                  ),
                  _InspectorMetaLine(
                    label: 'Duration',
                    value:
                        '${(info.duration ?? DateTime.now().difference(info.startedAt)).inMilliseconds} ms',
                  ),
                  if (info.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      info.error!.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffff8d8d),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: nodes.isEmpty
                ? const Center(child: Text('No node activity recorded.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: nodes.length,
                    itemBuilder: (context, index) => _ExecutionNodeInspectorRow(
                      snapshot: nodes[index],
                      editor: editor,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InspectorMetaLine extends StatelessWidget {
  const _InspectorMetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _ExecutionNodeInspectorRow extends StatelessWidget {
  const _ExecutionNodeInspectorRow({
    required this.snapshot,
    required this.editor,
  });

  final ExecutionTraceNodeSnapshot snapshot;
  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) {
    final editorId = snapshot.node.scope is MainGraphScope
        ? editor.editorNodeIdForSchema(snapshot.node.nodeId)
        : null;
    final title = editorId == null
        ? snapshot.node.nodeId
        : editor.nodeTitle(editorId);
    final statusColor = _nodeStatusColor(snapshot.status);
    final details = <String>[
      if (snapshot.duration != null) '${snapshot.duration!.inMilliseconds} ms',
      if (snapshot.invocationCount > 1) '×${snapshot.invocationCount}',
      if (snapshot.selectedPort != null) '→ ${snapshot.selectedPort}',
      if (snapshot.lastIteration != null) 'iteration ${snapshot.lastIteration}',
      if (snapshot.subgraphId != null) 'subgraph ${snapshot.subgraphId}',
    ];
    final result = snapshot.resultPreview;

    return InkWell(
      onTap: editorId == null
          ? null
          : () {
              editor.controller.selectNodesById({editorId});
              editor.controller.focusNodesById({editorId}, animate: true);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            Icon(
              _nodeStatusIcon(snapshot.status),
              size: 15,
              color: statusColor,
            ),
            const SizedBox(width: 7),
            Expanded(
              flex: 2,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                details.join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
            if (result != null)
              Expanded(
                flex: 3,
                child: Text(
                  _resultPreview(result),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xff9bd4ff),
                    fontFamily: 'Consolas',
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _nodeStatusColor(ExecutionTraceNodeStatus status) => switch (status) {
  ExecutionTraceNodeStatus.running => const Color(0xffe7bd62),
  ExecutionTraceNodeStatus.success => const Color(0xff65d6a0),
  ExecutionTraceNodeStatus.aborted => const Color(0xff9aa4b2),
  ExecutionTraceNodeStatus.error => const Color(0xffee7777),
};

IconData _nodeStatusIcon(ExecutionTraceNodeStatus status) => switch (status) {
  ExecutionTraceNodeStatus.running => Icons.circle,
  ExecutionTraceNodeStatus.success => Icons.check_circle,
  ExecutionTraceNodeStatus.aborted => Icons.cancel_outlined,
  ExecutionTraceNodeStatus.error => Icons.error,
};

String _resultPreview(Object value) {
  try {
    final encoded = value is String ? value : jsonEncode(value);
    return encoded.length > 120 ? '${encoded.substring(0, 117)}…' : encoded;
  } on Object {
    return value.toString();
  }
}

extension on List<ExecutionTraceRunSnapshot> {
  ExecutionTraceRunSnapshot? get firstOrNull => isEmpty ? null : first;
}

Color _executionStatusColor(ExecutionTraceRunStatus status) => switch (status) {
  ExecutionTraceRunStatus.starting ||
  ExecutionTraceRunStatus.running => const Color(0xffe7bd62),
  ExecutionTraceRunStatus.completed => const Color(0xff65d6a0),
  ExecutionTraceRunStatus.aborted => const Color(0xff9aa4b2),
  ExecutionTraceRunStatus.error => const Color(0xffee7777),
};

IconData _executionStatusIcon(ExecutionTraceRunStatus status) =>
    switch (status) {
      ExecutionTraceRunStatus.starting ||
      ExecutionTraceRunStatus.running => Icons.circle,
      ExecutionTraceRunStatus.completed => Icons.check_circle,
      ExecutionTraceRunStatus.aborted => Icons.cancel_outlined,
      ExecutionTraceRunStatus.error => Icons.error,
    };

String _executionStatusLabel(ExecutionTraceRunStatus status) =>
    switch (status) {
      ExecutionTraceRunStatus.starting => 'Starting',
      ExecutionTraceRunStatus.running => 'Running',
      ExecutionTraceRunStatus.completed => 'Completed',
      ExecutionTraceRunStatus.aborted => 'Aborted',
      ExecutionTraceRunStatus.error => 'Error',
    };
