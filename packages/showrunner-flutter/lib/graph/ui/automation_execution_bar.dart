import 'package:flutter/material.dart';
import '../execution/showrunner_execution_visual_adapter.dart';

/// Listens to runtime traces without rebuilding authoring controls.
class AutomationExecutionBar extends StatefulWidget {
  const AutomationExecutionBar({super.key, required this.execution});
  final ShowrunnerExecutionVisualAdapter execution;
  @override
  State<AutomationExecutionBar> createState() => _AutomationExecutionBarState();
}

class _AutomationExecutionBarState extends State<AutomationExecutionBar> {
  @override
  void initState() {
    super.initState();
    widget.execution.addListener(_changed);
  }

  @override
  void didUpdateWidget(AutomationExecutionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.execution != widget.execution) {
      oldWidget.execution.removeListener(_changed);
      widget.execution.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.execution.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final execution = widget.execution;
    final runs = execution.runs;
    if (runs.isEmpty) return const SizedBox.shrink();
    final pinned = execution.pinnedExecutionId;
    return Row(
      children: [
        const SizedBox(width: 8),
        const Text('Execution: '),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value:
                pinned != null &&
                    runs.any((run) => run.info.executionId == pinned)
                ? pinned
                : '',
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Live aggregate / latest run'),
              ),
              for (final run in runs)
                DropdownMenuItem(
                  value: run.info.executionId,
                  child: Text(
                    '${run.info.mode.name} · ${run.info.status.name} · ${run.info.startedAt.toLocal()}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => execution.pin(value == '' ? null : value),
          ),
        ),
      ],
    );
  }
}
