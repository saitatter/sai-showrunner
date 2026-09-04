import 'dart:io';

import 'package:flutter/material.dart';

import '../../persistence/queue_config_repository.dart';
import '../../runtime/action_queue.dart';
import '../../schema/queue.dart';
import '../../services/showrunner_data_service.dart';

class QueueWorkspace extends StatefulWidget {
  const QueueWorkspace({
    super.key,
    required this.dataService,
    required this.queue,
  });

  final ShowRunnerDataService dataService;
  final DartActionQueue queue;

  @override
  State<QueueWorkspace> createState() => _QueueWorkspaceState();
}

class _QueueWorkspaceState extends State<QueueWorkspace> {
  late final QueueConfigRepository _repository;
  List<({String fileName, QueueConfig? config, Object? error})> _entries = [];
  int? _selectedIndex;
  bool _loading = true;
  Object? _error;

  DartActionQueue get queue => widget.queue;
  QueueConfig? get selectedConfig =>
      _selectedIndex == null || _selectedIndex! >= _entries.length
      ? null
      : _entries[_selectedIndex!].config;

  @override
  void initState() {
    super.initState();
    _repository = QueueConfigRepository(
      Directory('${widget.dataService.userDirectory.path}/queues'),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _repository.list();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        if (_entries.isNotEmpty &&
            (_selectedIndex == null || _selectedIndex! >= _entries.length)) {
          _selectedIndex = 0;
        }
        queue.setPaused(selectedConfig?.paused ?? false);
        queue.defaultGap = selectedConfig?.gap ?? Duration.zero;
        queue.defaultTimeout = selectedConfig?.timeout;
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
    final fileName = 'queue_${DateTime.now().millisecondsSinceEpoch}.yaml';
    await _repository.save(fileName, const QueueConfig(name: 'New Queue'));
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
    final nameController = TextEditingController(text: config.name);
    final gapController = TextEditingController(
      text: config.gap.inSeconds.toString(),
    );
    final timeoutController = TextEditingController(
      text: config.timeout?.inSeconds.toString() ?? '',
    );
    var paused = config.paused;
    final result = await showDialog<QueueConfig>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit queue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                SwitchListTile(
                  title: const Text('Paused'),
                  value: paused,
                  onChanged: (value) => setDialogState(() => paused = value),
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Gap (seconds)'),
                  controller: gapController,
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Timeout (seconds)',
                  ),
                  controller: timeoutController,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                QueueConfig(
                  name: nameController.text.trim(),
                  paused: paused,
                  gap: Duration(seconds: int.tryParse(gapController.text) ?? 0),
                  timeout: timeoutController.text.trim().isEmpty
                      ? null
                      : Duration(
                          seconds: int.tryParse(timeoutController.text) ?? 30,
                        ),
                  extra: config.extra,
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    gapController.dispose();
    timeoutController.dispose();
    if (result == null || result.name.isEmpty) return;
    await _repository.save(fileName, result);
    await _load();
  }

  Future<void> _deleteQueue(String fileName) async {
    await _repository.delete(fileName);
    _selectedIndex = null;
    await _load();
  }

  void _replay(QueuedGraphExecution item) {
    queue.replay(item.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Queued replay of ${item.id}')));
  }

  void _skip(QueuedGraphExecution item) {
    queue.skip(item.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Skipped ${item.id}')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<QueuedGraphExecution?>(
      stream: queue.changes,
      initialData: queue.running,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Text('Queues', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: _createQueue,
                icon: const Icon(Icons.add),
                label: const Text('Create queue'),
              ),
            ],
          ),
          if (_error != null) Text('Error: $_error'),
          if (_entries.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.inbox),
                title: Text('No queues configured'),
              ),
            ),
          ..._entries.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final config = item.config;
            if (config == null) {
              return Card(
                child: ListTile(
                  title: Text(item.fileName),
                  subtitle: Text('Invalid queue: ${item.error}'),
                ),
              );
            }
            final selected = index == _selectedIndex;
            return Card(
              color: selected
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : null,
              child: ListTile(
                onTap: () {
                  setState(() => _selectedIndex = index);
                  queue.setPaused(config.paused);
                  queue.defaultGap = config.gap;
                  queue.defaultTimeout = config.timeout;
                },
                leading: Icon(
                  config.paused ? Icons.pause_circle : Icons.check_circle,
                ),
                title: Text(config.name),
                subtitle: Text(
                  '${config.paused ? 'Paused' : 'Ready'} | gap ${config.gap.inSeconds}s | ${queue.pending.length} pending | ${queue.history.length} recent',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Edit queue',
                      onPressed: () => _editQueue(config, item.fileName),
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'Delete queue',
                      onPressed: () => _deleteQueue(item.fileName),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                selectedConfig?.name ?? 'Runtime queue',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
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
          Text(
            queue.paused
                ? 'Paused'
                : queue.running != null
                ? 'Running'
                : 'Ready',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            children: [
              _QueueCount(label: 'Pending', value: queue.pending.length),
              _QueueCount(
                label: 'Running',
                value: queue.running == null ? 0 : 1,
              ),
              _QueueCount(label: 'Recent', value: queue.history.length),
            ],
          ),
          const SizedBox(height: 24),
          if (queue.running != null)
            _QueueItemTile(item: queue.running!, label: 'Running'),
          if (queue.pending.isNotEmpty) ...[
            const ListTile(title: Text('Pending')),
            ...queue.pending.map(
              (item) => _QueueItemTile(item: item, label: 'Pending'),
            ),
          ],
          if (queue.history.isNotEmpty) ...[
            const ListTile(title: Text('Recent history')),
            ...queue.history.map(
              (item) => _QueueItemTile(item: item, label: 'Completed'),
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
      ),
    );
  }
}

class _QueueItemTile extends StatelessWidget {
  const _QueueItemTile({required this.item, required this.label});

  final QueuedGraphExecution item;
  final String label;

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
              onPressed: () => context
                  .findAncestorStateOfType<_QueueWorkspaceState>()
                  ?._replay(item),
              icon: const Icon(Icons.replay),
            ),
          if (item.status == 'pending' || item.status == 'running')
            IconButton(
              tooltip: item.status == 'running' ? 'Cancel' : 'Skip',
              onPressed: () => context
                  .findAncestorStateOfType<_QueueWorkspaceState>()
                  ?._skip(item),
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
