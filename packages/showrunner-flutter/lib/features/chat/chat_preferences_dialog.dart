import 'package:flutter/material.dart';
import 'chat_message.dart';
import 'chat_preferences.dart';
import 'unified_chat_runtime.dart';

class ChatPreferencesDialog extends StatefulWidget {
  const ChatPreferencesDialog({super.key, required this.runtime});
  final UnifiedChatRuntime runtime;
  @override
  State<ChatPreferencesDialog> createState() => _ChatPreferencesDialogState();
}

class _ChatPreferencesDialogState extends State<ChatPreferencesDialog> {
  late final values = widget.runtime.preferences.toJson();
  late final ignored = TextEditingController(
    text: (values['ignoredUsers'] as List).join('\n'),
  );
  late final highlighted = TextEditingController(
    text: (values['highlightedUsers'] as List).join('\n'),
  );
  late final terms = TextEditingController(
    text: (values['highlightTerms'] as List).join('\n'),
  );
  late final rules = <(ChatRuleMode, TextEditingController)>[
    for (final rule in widget.runtime.preferences.ignoreRules)
      (rule.mode, TextEditingController(text: rule.pattern)),
  ];
  bool busy = false;
  Object? error;
  @override
  void dispose() {
    ignored.dispose();
    highlighted.dispose();
    terms.dispose();
    for (final rule in rules) {
      rule.$2.dispose();
    }
    super.dispose();
  }

  Widget toggle(String key, String label) => SwitchListTile(
    title: Text(label),
    value: values[key] as bool,
    onChanged: busy ? null : (value) => setState(() => values[key] = value),
  );
  Widget lines(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: label,
        helperText: 'One entry per line',
      ),
    ),
  );
  List<String> entries(TextEditingController controller) => controller.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.runtime.savePreferences(
        ChatPreferences.fromJson({
          ...values,
          'ignoredUsers': entries(ignored),
          'highlightedUsers': entries(highlighted),
          'highlightTerms': entries(terms),
          'ignoreRules': [
            for (final rule in rules)
              {'mode': rule.$1.name, 'pattern': rule.$2.text},
          ],
        }),
      );
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = failure;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Chat preferences'),
    content: SizedBox(
      width: 600,
      height: 480,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Display'),
                Tab(text: 'Ignores'),
                Tab(text: 'Highlights'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: values['font'] as String,
                        decoration: const InputDecoration(
                          labelText: 'Chat font',
                        ),
                        items: [
                          for (final font in ['system', 'monospace', 'serif'])
                            DropdownMenuItem(value: font, child: Text(font)),
                        ],
                        onChanged: busy
                            ? null
                            : (font) => setState(() => values['font'] = font),
                      ),
                      Text('Font size: ${(values['fontSize'] as num).round()}'),
                      Slider(
                        value: (values['fontSize'] as num).toDouble(),
                        min: 10,
                        max: 28,
                        divisions: 18,
                        onChanged: busy
                            ? null
                            : (size) =>
                                  setState(() => values['fontSize'] = size),
                      ),
                      toggle('timestamps', 'Show timestamps'),
                      toggle('newestFirst', 'Newest messages at top'),
                      toggle('alternatingRows', 'Alternate row backgrounds'),
                      toggle('platformIcons', 'Show platform icons'),
                      toggle('roleBadges', 'Show role labels'),
                      toggle('animatedEmotes', 'Animate emotes'),
                    ],
                  ),
                  ListView(
                    children: [
                      lines(ignored, 'Ignored user IDs (platform:userId)'),
                      toggle('hideCommands', 'Hide detected managed commands'),
                      toggle(
                        'preventIgnoredCommands',
                        'Also prevent ignored messages from running commands',
                      ),
                      const Text(
                        'By default, ignores hide messages only. Rules are case insensitive; regex uses a bounded worker.',
                      ),
                      for (final (index, rule) in rules.indexed)
                        Row(
                          children: [
                            DropdownButton<ChatRuleMode>(
                              value: rule.$1,
                              items: [
                                for (final mode in ChatRuleMode.values)
                                  DropdownMenuItem(
                                    value: mode,
                                    child: Text(mode.name),
                                  ),
                              ],
                              onChanged: busy
                                  ? null
                                  : (mode) => setState(
                                      () => rules[index] = (mode!, rule.$2),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: rule.$2,
                                decoration: const InputDecoration(
                                  labelText: 'Ignore pattern',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove ignore rule',
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() => rules.removeAt(index));
                                      // Dispose after the removed field has unmounted.
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => rule.$2.dispose(),
                                          );
                                    },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      TextButton.icon(
                        onPressed: busy || rules.length >= 32
                            ? null
                            : () => setState(
                                () => rules.add((
                                  ChatRuleMode.contains,
                                  TextEditingController(),
                                )),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add ignore rule'),
                      ),
                    ],
                  ),
                  ListView(
                    children: [
                      lines(terms, 'Highlight text or mentions'),
                      lines(
                        highlighted,
                        'Highlighted user IDs (platform:userId)',
                      ),
                      const Text('Highlight roles'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final role in ChatPermission.values)
                            FilterChip(
                              label: Text(role.name),
                              selected: (values['highlightedRoles'] as List)
                                  .contains(role.name),
                              onSelected: busy
                                  ? null
                                  : (selected) => setState(() {
                                      final roles =
                                          values['highlightedRoles'] as List;
                                      if (selected) {
                                        roles.add(role.name);
                                      } else {
                                        roles.remove(role.name);
                                      }
                                    }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (error != null)
        Text(
          '$error',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: const Text('Save preferences'),
      ),
    ],
  );
}
