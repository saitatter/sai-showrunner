import 'dashboard_editor_values.dart';
import 'package:flutter/material.dart';

class DashboardResourceSlotDialog extends StatefulWidget {
  const DashboardResourceSlotDialog({super.key});

  @override
  State<DashboardResourceSlotDialog> createState() =>
      _DashboardResourceSlotDialogState();
}

class _DashboardResourceSlotDialogState
    extends State<DashboardResourceSlotDialog> {
  final _name = TextEditingController();
  final _type = TextEditingController(text: 'SoundOutput');

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add resource slot'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _type,
          decoration: const InputDecoration(labelText: 'Slot type'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          final type = _type.text.trim();
          if (name.isEmpty || type.isEmpty) return;
          Navigator.pop(context, {
            'id': DashboardEditorValues.newId('slot'),
            'name': name,
            'slotType': type,
            'config': <String, dynamic>{},
          });
        },
        child: const Text('Add'),
      ),
    ],
  );
}
