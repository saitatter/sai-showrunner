import 'dart:io';
import 'package:flutter/material.dart';
import '../../persistence/automation_repository.dart';
import 'chat_message.dart';
import 'configured_chat_action.dart';
import 'unified_chat_runtime.dart';

IconData chatActionIcon(String icon) => switch (icon) {
  'star' => Icons.star_outline,
  'chat' => Icons.chat_bubble_outline,
  'person' => Icons.person_outline,
  'bolt' => Icons.bolt,
  _ => Icons.play_arrow,
};
Color? chatActionColor(String color) => switch (color) {
  'purple' => Colors.purpleAccent,
  'blue' => Colors.lightBlueAccent,
  'green' => Colors.lightGreenAccent,
  'orange' => Colors.orangeAccent,
  'red' => Colors.redAccent,
  _ => null,
};

class ChatActionsDialog extends StatefulWidget {
  const ChatActionsDialog({super.key, required this.runtime});
  final UnifiedChatRuntime runtime;
  @override
  State<ChatActionsDialog> createState() => _ChatActionsDialogState();
}

class _ChatActionsDialogState extends State<ChatActionsDialog> {
  bool busy = false;
  Object? error;
  Future<void> run(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (failure) {
      error = failure;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> edit([ConfiguredChatAction? action]) => run(() async {
    final catalog = await AutomationRepository.loadDirectory(
      Directory('${widget.runtime.dataService.userDirectory.path}/automations'),
    );
    if (!mounted) return;
    final result = await showDialog<ConfiguredChatAction>(
      context: context,
      builder: (_) => _ActionEditor(
        action: action,
        files: catalog.where((a) => a.isValid).map((a) => a.fileName).toList(),
      ),
    );
    if (result != null) {
      final actions = [...widget.runtime.configuredActions];
      final index = actions.indexWhere((a) => a.id == result.id);
      if (index < 0) {
        actions.add(result);
      } else {
        actions[index] = result;
      }
      await widget.runtime.saveActions(actions);
    }
  });
  Future<void> move(int index, int delta) => run(() async {
    final actions = [...widget.runtime.configuredActions];
    actions.insert(index + delta, actions.removeAt(index));
    await widget.runtime.saveActions(actions);
  });
  Future<void> remove(ConfiguredChatAction action) => run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${action.label}?'),
        content: const Text('The saved automation will be kept.'),
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
    if (confirmed == true) {
      await widget.runtime.saveActions(
        widget.runtime.configuredActions
            .where((a) => a.id != action.id)
            .toList(),
      );
    }
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Chat actions'),
    content: SizedBox(
      width: 700,
      height: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Run saved automations with global, message, user or event context. Reorder to change menu priority.',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy ? null : () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('New chat action'),
          ),
          if (error != null)
            Text(
              '$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final (index, action)
                    in widget.runtime.configuredActions.indexed)
                  ListTile(
                    leading: Icon(
                      chatActionIcon(action.icon),
                      color: chatActionColor(action.color),
                    ),
                    title: Text(action.label),
                    subtitle: Text(
                      '${action.scope.name} - ${action.automationFile} - ${action.enabled ? 'enabled' : 'disabled'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Move action up',
                          onPressed: busy || index == 0
                              ? null
                              : () => move(index, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Move action down',
                          onPressed:
                              busy ||
                                  index ==
                                      widget.runtime.configuredActions.length -
                                          1
                              ? null
                              : () => move(index, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          tooltip: 'Edit chat action',
                          onPressed: busy ? null : () => edit(action),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete chat action',
                          onPressed: busy ? null : () => remove(action),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({this.action, required this.files});
  final ConfiguredChatAction? action;
  final List<String> files;
  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late final label = TextEditingController(
    text: widget.action?.label ?? 'Chat action',
  );
  late final queue = TextEditingController(
    text: widget.action?.queueId ?? 'default',
  );
  late final arguments = TextEditingController(
    text:
        widget.action?.arguments.entries
            .map((e) => '${e.key}=${e.value}')
            .join('\n') ??
        '',
  );
  late String file =
      widget.action?.automationFile ?? widget.files.firstOrNull ?? '';
  late ChatActionScope scope = widget.action?.scope ?? ChatActionScope.message;
  late String icon = widget.action?.icon ?? 'play',
      color = widget.action?.color ?? 'default';
  late bool enabled = widget.action?.enabled ?? true;
  late final platforms = {
    ...?widget.action?.platforms,
    if (widget.action == null) ...ChatPlatform.values,
  };
  Object? error;
  @override
  void dispose() {
    label.dispose();
    queue.dispose();
    arguments.dispose();
    super.dispose();
  }

  void save() {
    try {
      final args = <String, String>{};
      for (final line
          in arguments.text.split('\n').where((s) => s.trim().isNotEmpty)) {
        final equals = line.indexOf('=');
        if (equals <= 0 || args.containsKey(line.substring(0, equals).trim())) {
          throw const FormatException('Use unique name=value argument lines.');
        }
        args[line.substring(0, equals).trim()] = line.substring(equals + 1);
      }
      final action = ConfiguredChatAction(
        id:
            widget.action?.id ??
            'action-${DateTime.now().microsecondsSinceEpoch}',
        label: label.text.trim(),
        automationFile: file,
        queueId: queue.text.trim(),
        scope: scope,
        enabled: enabled,
        icon: icon,
        color: color,
        platforms: platforms,
        arguments: args,
      );
      Navigator.pop(context, action);
    } catch (failure) {
      setState(() => error = failure);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.action == null ? 'New chat action' : 'Edit chat action'),
    content: SizedBox(
      width: 520,
      height: 480,
      child: ListView(
        children: [
          TextField(
            controller: label,
            decoration: const InputDecoration(labelText: 'Action label'),
          ),
          DropdownButtonFormField<String>(
            initialValue: file.isEmpty ? null : file,
            decoration: const InputDecoration(labelText: 'Automation'),
            items: [
              for (final name in {...widget.files, if (file.isNotEmpty) file})
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: (value) => setState(() => file = value!),
          ),
          if (widget.files.isEmpty)
            const Text('Save an automation before adding a chat action.'),
          TextField(
            controller: queue,
            decoration: const InputDecoration(labelText: 'Action queue ID'),
          ),
          DropdownButtonFormField<ChatActionScope>(
            initialValue: scope,
            decoration: const InputDecoration(labelText: 'Action scope'),
            items: [
              for (final value in ChatActionScope.values)
                DropdownMenuItem(value: value, child: Text(value.name)),
            ],
            onChanged: (value) => setState(() => scope = value!),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final platform in ChatPlatform.values)
                FilterChip(
                  label: Text(platform.name),
                  selected: platforms.contains(platform),
                  onSelected: (value) => setState(() {
                    if (value) {
                      platforms.add(platform);
                    } else {
                      platforms.remove(platform);
                    }
                  }),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: icon,
            decoration: const InputDecoration(labelText: 'Action icon'),
            items: [
              for (final value in ['play', 'star', 'chat', 'person', 'bolt'])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() => icon = value!),
          ),
          DropdownButtonFormField<String>(
            initialValue: color,
            decoration: const InputDecoration(labelText: 'Action color'),
            items: [
              for (final value in [
                'default',
                'purple',
                'blue',
                'green',
                'orange',
                'red',
              ])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() => color = value!),
          ),
          TextField(
            controller: arguments,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Action arguments',
              helperText:
                  'One name=value per line; available as actionArguments in the graph',
            ),
          ),
          SwitchListTile(
            title: const Text('Action enabled'),
            value: enabled,
            onChanged: (value) => setState(() => enabled = value),
          ),
          if (error != null)
            Text(
              '$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        onPressed: file.isEmpty ? null : save,
        child: const Text('Save chat action'),
      ),
    ],
  );
}
