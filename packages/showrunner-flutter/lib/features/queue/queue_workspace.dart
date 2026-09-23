import 'dart:io';

import 'package:flutter/material.dart';

import '../../persistence/queue_config_repository.dart';
import '../../app/app_feedback.dart';
import '../../runtime/action_queue.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../schema/queue.dart';
import '../../services/showrunner_data_service.dart';

class QueueWorkspace extends StatefulWidget {
  const QueueWorkspace({
    super.key,
    required this.dataService,
    required this.queue,
    this.queueManager,
  });

  final ShowRunnerDataService dataService;
  final DartActionQueue queue;
  final DartAutomationQueueManager? queueManager;

  @override
  State<QueueWorkspace> createState() => _QueueWorkspaceState();
}

class _QueueWorkspaceState extends State<QueueWorkspace> {
  late final QueueConfigRepository _repository;
  List<({String fileName, QueueConfig? config, Object? error})> _entries = [];
  int? _selectedIndex;
  bool _loading = true;
  Object? _error;
  late DartActionQueue _selectedQueue;

  DartActionQueue get queue => _selectedQueue;
  QueueConfig? get selectedConfig =>
      _selectedIndex == null || _selectedIndex! >= _entries.length
      ? null
      : _entries[_selectedIndex!].config;

  @override
  void initState() {
    super.initState();
    _selectedQueue = widget.queue;
    _repository = QueueConfigRepository(
      Directory('${widget.dataService.userDirectory.path}/queues'),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _repository.list();
      var selectedIndex = _selectedIndex;
      if (entries.isNotEmpty &&
          (selectedIndex == null || selectedIndex >= entries.length)) {
        selectedIndex = 0;
      }
      var selectedQueue = _selectedQueue;
      final selectedConfig = selectedIndex == null
          ? null
          : entries[selectedIndex].config;
      if (selectedConfig != null &&
          selectedIndex != null &&
          widget.queueManager != null) {
        selectedQueue = await widget.queueManager!.applyConfig(
          entries[selectedIndex].fileName,
          selectedConfig,
        );
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selectedIndex = selectedIndex;
        _selectedQueue = selectedQueue;
        if (selectedConfig != null && widget.queueManager == null) {
          _selectedQueue
            ..setPaused(selectedConfig.paused)
            ..defaultGap = selectedConfig.gap
            ..defaultTimeout = selectedConfig.timeout;
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _createQueue() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateQueueDialog(),
    );
    if (name == null || name.isEmpty) return;
    final fileName = 'queue_${DateTime.now().millisecondsSinceEpoch}.yaml';
    await _repository.save(fileName, QueueConfig(name: name));
    await widget.queueManager?.applyConfig(fileName, QueueConfig(name: name));
    await _load();
    if (mounted) {
      setState(
        () => _selectedIndex = _entries.indexWhere(
          (entry) => entry.fileName == fileName,
        ),
      );
    }
  }

  Future<void> _editQueue(QueueConfig config, String fileName) async {
    final result = await showDialog<QueueConfig>(
      context: context,
      builder: (_) => _EditQueueDialog(config: config),
    );
    if (result == null || result.name.isEmpty) return;
    await _repository.save(fileName, result);
    await widget.queueManager?.applyConfig(fileName, result);
    await _load();
  }

  Future<void> _deleteQueue(String fileName) async {
    await _repository.delete(fileName);
    _selectedIndex = null;
    if (widget.queueManager?.registeredQueue(fileName) case final queue?) {
      queue.clearPending();
    }
    await _load();
  }

  Future<void> _selectQueue(
    int index,
    String fileName,
    QueueConfig config,
  ) async {
    try {
      final selected = widget.queueManager == null
          ? widget.queue
          : await widget.queueManager!.applyConfig(fileName, config);
      if (!mounted) return;
      setState(() {
        _selectedIndex = index;
        _selectedQueue = selected;
        if (widget.queueManager == null) {
          _selectedQueue
            ..setPaused(config.paused)
            ..defaultGap = config.gap
            ..defaultTimeout = config.timeout;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _replay(QueuedGraphExecution item) {
    queue.replay(item.id);
    showShowRunnerFeedback(
      context,
      'Queued replay of ${item.id}',
      severity: ShowRunnerFeedbackSeverity.info,
    );
  }

  void _skip(QueuedGraphExecution item) {
    queue.skip(item.id);
    showShowRunnerFeedback(
      context,
      'Skipped ${item.id}',
      severity: ShowRunnerFeedbackSeverity.info,
    );
  }

  DartActionQueue? _queueForEntry(int index, String fileName) {
    if (index == _selectedIndex) return queue;
    return widget.queueManager?.registeredQueue(fileName);
  }

  Future<void> _showRuntimeQueue() => showDialog<void>(
    context: context,
    builder: (dialogContext) => StreamBuilder<QueuedGraphExecution?>(
      stream: queue.changes,
      initialData: queue.running,
      builder: (context, _) => AlertDialog(
        title: Text(selectedConfig?.name ?? 'Default runtime queue'),
        content: SizedBox(
          width: 680,
          height: 520,
          child: _runtimeQueueDetails(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  Widget _runtimeQueueDetails(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              queue.paused
                  ? 'Paused'
                  : queue.running != null
                  ? 'Running'
                  : 'Ready',
            ),
          ),
          IconButton(
            tooltip: queue.paused ? 'Resume queue' : 'Pause queue',
            onPressed: () => queue.setPaused(!queue.paused),
            icon: Icon(queue.paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: 'Clear pending actions',
            onPressed: queue.pending.isEmpty ? null : queue.clearPending,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      Wrap(
        spacing: 24,
        children: [
          _QueueCount(label: 'Pending', value: queue.pending.length),
          _QueueCount(label: 'Running', value: queue.running == null ? 0 : 1),
          _QueueCount(label: 'Recent', value: queue.history.length),
        ],
      ),
      const SizedBox(height: 12),
      if (queue.running != null)
        _QueueItemTile(
          item: queue.running!,
          label: 'Running',
          onReplay: _replay,
          onSkip: _skip,
        ),
      if (queue.pending.isNotEmpty) ...[
        const ListTile(title: Text('Pending')),
        ...queue.pending.map(
          (item) => _QueueItemTile(
            item: item,
            label: 'Pending',
            onReplay: _replay,
            onSkip: _skip,
          ),
        ),
      ],
      if (queue.history.isNotEmpty) ...[
        const ListTile(title: Text('Recent history')),
        ...queue.history.map(
          (item) => _QueueItemTile(
            item: item,
            label: 'Completed',
            onReplay: _replay,
            onSkip: _skip,
          ),
        ),
      ],
      if (queue.pending.isEmpty &&
          queue.running == null &&
          queue.history.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.inbox),
            title: Text('Queue is empty'),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<QueuedGraphExecution?>(
      stream: queue.changes,
      initialData: queue.running,
      builder: (context, snapshot) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Queues',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Queues schedule graph automations for alerts, scene banners, paid events, and other moments that should not overlap.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open runtime queue',
                  onPressed: _showRuntimeQueue,
                  icon: Badge(
                    isLabelVisible:
                        queue.pending.isNotEmpty || queue.running != null,
                    label: Text('${queue.pending.length}'),
                    child: const Icon(Icons.queue_play_next),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _createQueue,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Queue'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text('Error: $_error'),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 28,
                    columns: const [
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Current Item')),
                      DataColumn(label: Text('Pending'), numeric: true),
                      DataColumn(label: Text('Recent'), numeric: true),
                      DataColumn(label: Text('Next Automation')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final entry in _entries.asMap().entries)
                        _queueRow(context, entry.key, entry.value),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _queueRow(
    BuildContext context,
    int index,
    ({String fileName, QueueConfig? config, Object? error}) entry,
  ) {
    final config = entry.config;
    if (config == null) {
      return DataRow(
        cells: [
          const DataCell(Text('Error')),
          DataCell(Text(entry.fileName)),
          DataCell(Text('Invalid queue: ${entry.error}')),
          const DataCell(Text('—')),
          const DataCell(Text('—')),
          const DataCell(Text('—')),
          const DataCell(SizedBox.shrink()),
        ],
      );
    }
    final runtimeQueue = _queueForEntry(index, entry.fileName);
    final running = runtimeQueue?.running;
    final pending = runtimeQueue?.pending ?? const <QueuedGraphExecution>[];
    final state = config.paused
        ? 'Paused'
        : running != null
        ? 'Running'
        : 'Ready';
    final source = running ?? (pending.isEmpty ? null : pending.first);
    return DataRow(
      selected: index == _selectedIndex,
      onSelectChanged: (_) => _selectQueue(index, entry.fileName, config),
      cells: [
        DataCell(_QueueStatusPill(state: state)),
        DataCell(Text(config.name)),
        DataCell(Text(source == null ? 'Idle' : _describeQueueSource(source))),
        DataCell(Text('${pending.length}')),
        DataCell(Text('${runtimeQueue?.history.length ?? 0}')),
        DataCell(
          Text(
            pending.isEmpty
                ? 'No pending items'
                : _describeQueueSource(pending.first),
          ),
        ),
        DataCell(
          Wrap(
            spacing: 0,
            children: [
              IconButton(
                tooltip: 'Edit queue',
                visualDensity: VisualDensity.compact,
                onPressed: () => _editQueue(config, entry.fileName),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Delete queue',
                visualDensity: VisualDensity.compact,
                onPressed: () => _deleteQueue(entry.fileName),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _describeQueueSource(QueuedGraphExecution item) {
    final sourceType = item.source['sourceType']?.toString();
    final sourceId = item.source['sourceId']?.toString();
    final subId = item.source['sourceSubId']?.toString();
    if (sourceType == 'profile') {
      return 'Profile trigger ${subId ?? sourceId ?? item.id}';
    }
    if (sourceType == 'stream-plan') {
      return 'Stream plan ${subId ?? sourceId ?? item.id}';
    }
    if (sourceType != null && sourceId != null) {
      return '$sourceType:${subId ?? sourceId}';
    }
    return item.source['name']?.toString() ?? 'Automation ${item.id}';
  }
}

class _CreateQueueDialog extends StatefulWidget {
  const _CreateQueueDialog();

  @override
  State<_CreateQueueDialog> createState() => _CreateQueueDialogState();
}

class _CreateQueueDialogState extends State<_CreateQueueDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create queue'),
    content: TextField(
      autofocus: true,
      controller: _nameController,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}

class _EditQueueDialog extends StatefulWidget {
  const _EditQueueDialog({required this.config});

  final QueueConfig config;

  @override
  State<_EditQueueDialog> createState() => _EditQueueDialogState();
}

class _EditQueueDialogState extends State<_EditQueueDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _gapController;
  late final TextEditingController _timeoutController;
  late bool _paused;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.config.name);
    _gapController = TextEditingController(
      text: widget.config.gap.inSeconds.toString(),
    );
    _timeoutController = TextEditingController(
      text: widget.config.timeout?.inSeconds.toString() ?? '',
    );
    _paused = widget.config.paused;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gapController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      QueueConfig(
        name: name,
        paused: _paused,
        gap: Duration(seconds: int.tryParse(_gapController.text) ?? 0),
        timeout: _timeoutController.text.trim().isEmpty
            ? null
            : Duration(seconds: int.tryParse(_timeoutController.text) ?? 30),
        extra: widget.config.extra,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit queue'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          SwitchListTile(
            title: const Text('Paused'),
            value: _paused,
            onChanged: (value) => setState(() => _paused = value),
          ),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Gap (seconds)'),
            controller: _gapController,
          ),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Timeout (seconds)'),
            controller: _timeoutController,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _QueueStatusPill extends StatelessWidget {
  const _QueueStatusPill({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (state) {
      'Running' => (Icons.play_circle_outline, Colors.green.shade300),
      'Paused' => (Icons.pause, Colors.amber.shade300),
      _ => (Icons.check_circle_outline, colors.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .42)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(state),
        ],
      ),
    );
  }
}

class _QueueItemTile extends StatelessWidget {
  const _QueueItemTile({
    required this.item,
    required this.label,
    required this.onReplay,
    required this.onSkip,
  });

  final QueuedGraphExecution item;
  final String label;
  final ValueChanged<QueuedGraphExecution> onReplay;
  final ValueChanged<QueuedGraphExecution> onSkip;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        item.status == 'failed' ? Icons.error_outline : Icons.bolt,
        color: item.status == 'failed' ? Colors.redAccent : null,
      ),
      title: Text(item.source['name']?.toString() ?? item.id),
      subtitle: Text(
        [
          label,
          item.status,
          if (item.duration != null) '${item.duration!.inMilliseconds} ms',
          if (item.reason != null) item.reason!,
          if (item.error != null) item.error!,
        ].join(' | '),
      ),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (item.status == 'completed' || item.status == 'failed')
            IconButton(
              tooltip: 'Replay',
              onPressed: () => onReplay(item),
              icon: const Icon(Icons.replay),
            ),
          if (item.status == 'pending' || item.status == 'running')
            IconButton(
              tooltip: item.status == 'running' ? 'Cancel' : 'Skip',
              onPressed: () => onSkip(item),
              icon: Icon(
                item.status == 'running' ? Icons.stop_circle : Icons.skip_next,
              ),
            ),
          Text(item.id),
        ],
      ),
    ),
  );
}

class _QueueCount extends StatelessWidget {
  const _QueueCount({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$value', style: Theme.of(context).textTheme.headlineMedium),
      Text(label),
    ],
  );
}
