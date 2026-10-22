import 'package:flutter/material.dart';
import '../../plugins/registry/plugin_registry.dart';

class ProfileTriggerPickerDialog extends StatelessWidget {
  const ProfileTriggerPickerDialog({super.key, required this.registry});

  final DartPluginRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final triggers = [
      for (final plugin in registry?.plugins ?? const <DartPluginManifest>[])
        for (final trigger in plugin.triggers) trigger,
    ];
    return AlertDialog(
      title: const Text('Add profile trigger'),
      content: SizedBox(
        width: 420,
        child: triggers.isEmpty
            ? const Text('No registered triggers are available.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final trigger in triggers)
                    ListTile(
                      leading: const Icon(Icons.bolt),
                      title: Text(trigger.displayName),
                      subtitle: Text(
                        '${trigger.pluginId}:${trigger.triggerId}',
                      ),
                      onTap: () => Navigator.of(context).pop(trigger),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
