import 'package:flutter/material.dart';

import '../../runtime/action_queue.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../design_system/workspace_notice.dart';

import 'dashboard_widgets.dart';

class QueueDashboardCard extends StatefulWidget {
  const QueueDashboardCard({
    super.key,
    required this.name,
    this.queueManager,
    this.queueId,
    required this.queue,
    required this.onOpen,
  });

  final String name;
  final DartActionQueue queue;
  final DartAutomationQueueManager? queueManager;
  final String? queueId;
  final VoidCallback onOpen;

  @override
  State<QueueDashboardCard> createState() => _QueueDashboardCardState();
}

class _QueueDashboardCardState extends State<QueueDashboardCard> {
  late Future<DartActionQueue> _queue = _load();
  Future<DartActionQueue> _load() => widget.queueManager == null
      ? Future.value(widget.queue)
      : widget.queueManager!.queueFor(widget.queueId);
  @override
  void didUpdateWidget(QueueDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue != widget.queue ||
        oldWidget.queueManager != widget.queueManager ||
        oldWidget.queueId != widget.queueId) {
      _queue = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DartActionQueue>(
    future: _queue,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const LinearProgressIndicator();
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return WorkspaceNotice(
          title: widget.name,
          message: 'Queue status is unavailable.',
          action: TextButton(
            onPressed: () => setState(() {
              _queue = _load();
            }),
            child: const Text('Retry'),
          ),
        );
      }
      final queue = snapshot.data!;
      return StreamBuilder<QueuedGraphExecution?>(
        stream: queue.changes,
        builder: (context, _) => DashboardCard(
          icon: Icons.queue_music,
          title: widget.name,
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    DashboardStatItem(
                      label: 'Pending',
                      value: '${queue.pending.length}',
                    ),
                    DashboardStatItem(
                      label: 'Running',
                      value: queue.running == null ? '0' : '1',
                    ),
                    DashboardStatItem(
                      label: 'History',
                      value: '${queue.history.length}',
                    ),
                  ],
                ),
              ),
              Icon(
                queue.paused ? Icons.pause_circle : Icons.play_circle,
                color: queue.paused ? Colors.orange : Colors.green,
              ),
              IconButton(
                tooltip: 'Open queues',
                onPressed: widget.onOpen,
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        ),
      );
    },
  );
}
