import 'dart:io';
import 'package:flutter/material.dart';
import '../../persistence/automation_repository.dart';
import '../../services/showrunner_data_service.dart';
import 'chat_command.dart';
import 'chat_message.dart';
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
  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _edit([ChatCommand? command]) => _run(() async {
    final catalog = await AutomationRepository.loadDirectory(
      Directory('${widget.dataService.userDirectory.path}/automations'),
    );
    final files = catalog
        .where((a) => a.isValid)
        .map((a) => a.fileName)
        .toList();
    if (!mounted) return;
    final result = await showDialog<ChatCommand>(
      context: context,
      builder: (context) => _CommandEditor(command: command, files: files),
    );
    if (result != null) await widget.manager.save(result);
  });
  Future<void> _delete(ChatCommand command) async {
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
    if (confirmed == true) await _run(() => widget.manager.delete(command.id));
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
            if (_error ?? manager.error case final Object error)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  '$error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
                                              index ==
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

class _CommandEditor extends StatefulWidget {
  const _CommandEditor({this.command, required this.files});
  final ChatCommand? command;
  final List<String> files;
  @override
  State<_CommandEditor> createState() => _CommandEditorState();
}

class _CommandEditorState extends State<_CommandEditor> {
  final _fields = <String, TextEditingController>{};
  String? _file;
  late CommandMatchMode _mode;
  late CommandArgumentMode _arguments;
  late ChatPermission _permission;
  late CommandGrant _grant;
  late Set<ChatPermission> _roles;
  late Set<ChatOrigin> _origins;
  late bool _ignoreBots,
      _ignoreInternal,
      _bypass,
      _persist,
      _persistUsers,
      _include;
  late Set<ChatPlatform> _platforms;
  late bool _enabled, _caseSensitive;
  Object? _error;
  @override
  void initState() {
    super.initState();
    final c = widget.command;
    final values = {
      'Name': c?.name ?? '',
      'Pattern': c?.pattern ?? '!hello',
      'Aliases (comma separated)': c?.aliases.join(', ') ?? '',
      'Global cooldown (seconds)':
          '${(c?.globalCooldown.inMilliseconds ?? 0) / 1000}',
      'User cooldown (seconds)':
          '${(c?.userCooldown.inMilliseconds ?? 0) / 1000}',
      'Minimum arguments': '${c?.minimumArguments ?? 0}',
      'Queue ID': c?.queueId ?? 'default',
      'Group': c?.group ?? '',
      'User IDs (platform:userId, comma separated)': c?.users.join(', ') ?? '',
      'Viewer group IDs (comma separated)': c?.groups.join(', ') ?? '',
    };
    for (final entry in values.entries) {
      _fields[entry.key] = TextEditingController(text: entry.value);
    }
    _file =
        c?.automationFile ?? (widget.files.isEmpty ? null : widget.files.first);
    _mode = c?.matchMode ?? CommandMatchMode.command;
    _arguments = c?.argumentMode ?? CommandArgumentMode.quoted;
    _permission = c?.permission ?? ChatPermission.everyone;
    _grant = c?.grant ?? CommandGrant.allow;
    _roles = {...?c?.roles};
    _origins = c == null ? {ChatOrigin.chat} : {...c.origins};
    _ignoreBots = c?.ignoreBots ?? true;
    _ignoreInternal = c?.ignoreInternal ?? true;
    _bypass = c?.broadcasterBypass ?? false;
    _persist = c?.persistCounter ?? true;
    _persistUsers = c?.persistUserCounter ?? true;
    _include = c?.includeInList ?? true;
    _platforms = {...?c?.platforms};
    if (c == null) _platforms.addAll(ChatPlatform.values);
    _enabled = c?.enabled ?? true;
    _caseSensitive = c?.caseSensitive ?? false;
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _save() {
    try {
      String value(String key) => _fields[key]!.text.trim();
      Duration duration(String key) {
        final seconds = double.tryParse(value(key));
        if (seconds == null ||
            !seconds.isFinite ||
            seconds < 0 ||
            seconds > 86400) {
          throw FormatException('$key must be between 0 and 86400.');
        }
        return Duration(milliseconds: (seconds * 1000).round());
      }

      if (_file == null || !widget.files.contains(_file)) {
        throw const FormatException('Select an existing automation.');
      }
      final minimum = int.tryParse(value('Minimum arguments'));
      if (minimum == null || minimum < 0) {
        throw const FormatException(
          'Minimum arguments must be a nonnegative integer.',
        );
      }
      if (value('Queue ID').isEmpty) {
        throw const FormatException('Queue ID is required.');
      }
      final command = ChatCommand(
        id:
            widget.command?.id ??
            'command-${DateTime.now().microsecondsSinceEpoch}',
        name: value('Name'),
        pattern: value('Pattern'),
        automationFile: _file!,
        aliases: value('Aliases (comma separated)')
            .split(_mode == CommandMatchMode.regex ? '\n' : ',')
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList(),
        platforms: _platforms,
        enabled: _enabled,
        caseSensitive: _caseSensitive,
        matchMode: _mode,
        argumentMode: _arguments,
        permission: _permission,
        grant: _grant,
        roles: _roles,
        origins: _origins,
        users: value(
          'User IDs (platform:userId, comma separated)',
        ).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet(),
        groups: value(
          'Viewer group IDs (comma separated)',
        ).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet(),
        ignoreBots: _ignoreBots,
        ignoreInternal: _ignoreInternal,
        broadcasterBypass: _bypass,
        persistCounter: _persist,
        persistUserCounter: _persistUsers,
        group: value('Group'),
        includeInList: _include,
        minimumArguments: minimum,
        globalCooldown: duration('Global cooldown (seconds)'),
        userCooldown: duration('User cooldown (seconds)'),
        queueId: value('Queue ID'),
      );
      Navigator.pop(context, command);
    } catch (error) {
      setState(() => _error = error);
    }
  }

  Widget _select<T>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(v.toString().split('.').last),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => onChanged(value));
      },
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.command == null ? 'New chat command' : 'Edit chat command',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in _fields.entries.where(
              (e) =>
                  !e.key.startsWith('User IDs') &&
                  !e.key.startsWith('Viewer group IDs'),
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextField(
                  controller: entry.value,
                  maxLines:
                      entry.key == 'Aliases (comma separated)' &&
                          _mode == CommandMatchMode.regex
                      ? 3
                      : 1,
                  decoration: InputDecoration(
                    labelText:
                        entry.key == 'Aliases (comma separated)' &&
                            _mode == CommandMatchMode.regex
                        ? 'Aliases (one regex per line)'
                        : entry.key,
                  ),
                ),
              ),
            if (widget.files.isEmpty)
              const Text('Create and save an automation first.'),
            DropdownButtonFormField<String>(
              initialValue: widget.files.contains(_file) ? _file : null,
              decoration: const InputDecoration(labelText: 'Automation'),
              items: widget.files
                  .map(
                    (file) => DropdownMenuItem(value: file, child: Text(file)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _file = v),
            ),
            _select(
              'Match mode',
              _mode,
              CommandMatchMode.values,
              (v) => _mode = v,
            ),
            _select(
              'Argument parsing',
              _arguments,
              CommandArgumentMode.values,
              (v) => _arguments = v,
            ),
            _select(
              'Permission',
              _permission,
              ChatPermission.values,
              (v) => _permission = v,
            ),
            Wrap(
              spacing: 10,
              children: [
                for (final platform in ChatPlatform.values)
                  FilterChip(
                    label: Text(platform.name),
                    selected: _platforms.contains(platform),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _platforms.add(platform);
                      } else {
                        _platforms.remove(platform);
                      }
                    }),
                  ),
              ],
            ),
            const Text('Message sources'),
            Wrap(
              spacing: 8,
              children: [
                for (final origin in ChatOrigin.values)
                  FilterChip(
                    label: Text(origin.name),
                    selected: _origins.contains(origin),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _origins.add(origin);
                      } else {
                        _origins.remove(origin);
                      }
                    }),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text('Advanced access rules'),
              children: [
                for (final entry in _fields.entries.where(
                  (e) =>
                      e.key.startsWith('User IDs') ||
                      e.key.startsWith('Viewer group IDs'),
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: TextField(
                      controller: entry.value,
                      decoration: InputDecoration(labelText: entry.key),
                    ),
                  ),
                _select(
                  'Grant rule',
                  _grant,
                  CommandGrant.values,
                  (v) => _grant = v,
                ),
                const Text(
                  'Roles, users and viewer groups are alternatives within the grant rule. An empty Allow allows everyone; an empty Deny denies everyone.',
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final role in ChatPermission.values.where(
                      (r) => r != ChatPermission.everyone,
                    ))
                      FilterChip(
                        label: Text('Rule: ${role.name}'),
                        selected: _roles.contains(role),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _roles.add(role);
                          } else {
                            _roles.remove(role);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Ignore bot accounts'),
              value: _ignoreBots,
              onChanged: (v) => setState(() => _ignoreBots = v),
            ),
            SwitchListTile(
              title: const Text('Ignore internal messages'),
              value: _ignoreInternal,
              onChanged: (v) => setState(() => _ignoreInternal = v),
            ),
            SwitchListTile(
              title: const Text(
                'Broadcaster bypasses permissions and cooldowns',
              ),
              value: _bypass,
              onChanged: (v) => setState(() => _bypass = v),
            ),
            SwitchListTile(
              title: const Text('Persist total counters'),
              value: _persist,
              onChanged: (v) => setState(() => _persist = v),
            ),
            SwitchListTile(
              title: const Text('Persist user counters'),
              value: _persistUsers,
              onChanged: (v) => setState(() => _persistUsers = v),
            ),
            SwitchListTile(
              title: const Text('Include in command suggestions and lists'),
              value: _include,
              onChanged: (v) => setState(() => _include = v),
            ),
            SwitchListTile(
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            SwitchListTile(
              title: const Text('Case sensitive'),
              value: _caseSensitive,
              onChanged: (v) => setState(() => _caseSensitive = v),
            ),
            if (_error != null)
              Text(
                '$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save command')),
    ],
  );
}
