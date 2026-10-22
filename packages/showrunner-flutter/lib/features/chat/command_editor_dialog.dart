import 'package:flutter/material.dart';
import 'chat_command.dart';
import 'chat_message.dart';

class CommandEditorDialog extends StatefulWidget {
  const CommandEditorDialog({super.key, this.command, required this.files});
  final ChatCommand? command;
  final List<String> files;
  @override
  State<CommandEditorDialog> createState() => CommandEditorDialogState();
}

class CommandEditorDialogState extends State<CommandEditorDialog> {
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
