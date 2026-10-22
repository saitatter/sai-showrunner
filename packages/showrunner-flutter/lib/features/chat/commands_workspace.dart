import 'package:flutter/material.dart';
import '../../services/showrunner_data_service.dart';
import 'chat_command.dart';
import 'command_editor_dialog.dart';
import '../../design_system/workspace_notice.dart';
import 'command_manager.dart';

class CommandsWorkspace extends StatefulWidget {
  const CommandsWorkspace({
    super.key,
    required this.manager,
    required this.dataService,
  });
  final ChatCommandManager manager;
  final ShowRunnerDataService dataService;
  @override
  State<CommandsWorkspace> createState() => _CommandsWorkspaceState();
}

class _CommandsWorkspaceState extends State<CommandsWorkspace> {
  Object? _error;
  bool _busy = false;
  String _query = "";
  Object _owner = Object();
  bool _isCurrent(Object owner) => mounted && identical(owner, _owner);

  @override
  void didUpdateWidget(covariant CommandsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager ||
        oldWidget.dataService != widget.dataService) {
      _owner = Object();
      _busy = false;
      _error = null;
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || !mounted) return;
    final owner = _owner;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (_isCurrent(owner)) _error = error;
    }
    if (_isCurrent(owner)) setState(() => _busy = false);
  }

  Future<void> _edit([ChatCommand? command]) => _run(() async {
    final owner = _owner;
    final manager = widget.manager;
    final catalog = await widget.dataService.storage.listAutomations();
    final files = catalog
        .where((a) => a.isValid)
        .map((a) => a.fileName)
        .toList();
    if (!mounted || !_isCurrent(owner)) return;
    final result = await showDialog<ChatCommand>(
      context: context,
      builder: (context) => CommandEditorDialog(command: command, files: files),
    );
    if (result != null && _isCurrent(owner)) await manager.save(result);
  });
  Future<void> _delete(ChatCommand command) async {
    final owner = _owner;
    final manager = widget.manager;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${command.name}?'),
        content: const Text(
          'The automation and historical counters will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && _isCurrent(owner)) {
      await _run(() => manager.delete(command.id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.manager,
    builder: (context, _) {
      final manager = widget.manager;
      final visible = manager.commands
          .where(
            (c) => '${c.name} ${c.pattern} ${c.aliases.join(' ')} ${c.group}'
                .toLowerCase()
                .contains(_query.toLowerCase()),
          )
          .toList();
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Chat Commands',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                FilledButton.icon(
                  onPressed: _busy || !manager.loaded ? null : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('New command'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search commands or groups',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const Text(
              'Commands run independently of profiles. The first matching command wins; automations execute through their selected queue.',
            ),
            if (_error != null || manager.error != null)
              const WorkspaceNotice(
                message:
                    'Command operation failed. Check the configuration and retry.',
              ),
            if (!manager.loaded)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : () => _run(manager.load),
                  child: const Text('Retry loading commands'),
                ),
              ),
            if (manager.lastDecision != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(manager.lastDecision!),
              ),
            Expanded(
              child: manager.commands.isEmpty
                  ? const Center(
                      child: Text(
                        'No commands yet. Save an automation, then connect it to a command.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final command = visible[index];
                        final priority = manager.commands.indexOf(command);
                        final count = manager.countersFor(command.id);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Switch(
                                      value: command.enabled,
                                      onChanged: _busy
                                          ? null
                                          : (value) => _run(
                                              () => manager.save(
                                                ChatCommand.fromJson({
                                                  ...command.toJson(),
                                                  'enabled': value,
                                                }),
                                              ),
                                            ),
                                    ),
                                    Text(
                                      command.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Chip(label: Text(command.pattern)),
                                    Text(
                                      command.platforms
                                          .map((p) => p.name)
                                          .join(' · '),
                                    ),
                                    IconButton(
                                      tooltip: 'Move command up',
                                      onPressed: _busy || priority == 0
                                          ? null
                                          : () => _run(
                                              () =>
                                                  manager.move(command.id, -1),
                                            ),
                                      icon: const Icon(Icons.arrow_upward),
                                    ),
                                    IconButton(
                                      tooltip: 'Move command down',
                                      onPressed:
                                          _busy ||
                                              priority ==
                                                  manager.commands.length - 1
                                          ? null
                                          : () => _run(
                                              () => manager.move(command.id, 1),
                                            ),
                                      icon: const Icon(Icons.arrow_downward),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit command',
                                      onPressed: _busy
                                          ? null
                                          : () => _edit(command),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete command',
                                      onPressed: _busy
                                          ? null
                                          : () => _delete(command),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${command.automationFile} · ${command.matchMode.name} · ${command.permission.name} · ${command.grant.name} rule · queue ${command.queueId}',
                                ),
                                if (command.aliases.isNotEmpty)
                                  Text(
                                    'Aliases: ${command.aliases.join(', ')}',
                                  ),
                                Text(
                                  'Cooldown: global ${command.globalCooldown.inMilliseconds / 1000}s / user ${command.userCooldown.inMilliseconds / 1000}s',
                                ),
                                Wrap(
                                  spacing: 16,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${count.accepted} accepted · ${count.dispatched} queued · ${count.failed} failed · ${count.users.length} users',
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => manager.resetCounters(
                                                command.id,
                                              ),
                                            ),
                                      child: const Text('Reset counters'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => manager.resetUserCounters(
                                                command.id,
                                              ),
                                            ),
                                      child: const Text('Reset user counters'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => manager.resetCooldowns(
                                                command.id,
                                              ),
                                            ),
                                      child: const Text('Reset cooldowns'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
