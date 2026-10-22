import 'package:flutter/material.dart';
import 'resource_editor_registry.dart';

class NewResourceDialog extends StatefulWidget {
  const NewResourceDialog({
    super.key,
    required this.editorRegistry,
    this.resourceType,
    this.resourceTypes,
  });

  final DartResourceEditorRegistry editorRegistry;
  final String? resourceType;
  final Set<String>? resourceTypes;

  @override
  State<NewResourceDialog> createState() => NewResourceDialogState();
}

class NewResourceDialogState extends State<NewResourceDialog> {
  final _name = TextEditingController();
  late final List<String> _types;
  late String _type;

  @override
  void initState() {
    super.initState();
    _types = widget.resourceType == null
        ? widget.editorRegistry.definitions
              .map((def) => def.resourceType)
              .where(
                (type) =>
                    widget.resourceTypes == null ||
                    widget.resourceTypes!.contains(type),
              )
              .toList()
        : [widget.resourceType!];
    _type = _types.firstOrNull ?? 'Overlay';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New resource'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [
            for (final type in _types)
              DropdownMenuItem(value: type, child: Text(type)),
          ],
          onChanged: (value) => setState(() => _type = value ?? _types.first),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_type, _name.text.trim())),
        child: const Text('Create'),
      ),
    ],
  );
}
