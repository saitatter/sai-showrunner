part of '../resource_editor_registry.dart';

class _VariableEditor extends StatefulWidget {
  const _VariableEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_VariableEditor> createState() => _VariableEditorState();
}

class _VariableEditorState extends State<_VariableEditor> {
  late final TextEditingController _name;
  late final TextEditingController _type;
  late final TextEditingController _defaultValue;
  late final TextEditingController _currentValue;
  late bool _persistent;

  @override
  void initState() {
    super.initState();
    final variable = VariableResource.fromResource(widget.resource);
    _name = TextEditingController(text: variable.name);
    _type = TextEditingController(text: variable.type);
    _defaultValue = TextEditingController(
      text: '${variable.defaultValue ?? ''}',
    );
    _currentValue = TextEditingController(
      text: '${variable.currentValue ?? ''}',
    );
    _persistent = variable.persistent;
  }

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _defaultValue.dispose();
    _currentValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit variable',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _type,
        decoration: const InputDecoration(labelText: 'Type'),
      ),
      TextField(
        controller: _defaultValue,
        decoration: const InputDecoration(labelText: 'Default value'),
      ),
      TextField(
        controller: _currentValue,
        decoration: const InputDecoration(labelText: 'Current value'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Persistent'),
        value: _persistent,
        onChanged: (value) => setState(() => _persistent = value),
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'type': _type.text.trim(),
          'defaultValue': _defaultValue.text,
          'persistent': _persistent,
        },
        state: {'value': _currentValue.text},
      ),
    ),
  );
}
