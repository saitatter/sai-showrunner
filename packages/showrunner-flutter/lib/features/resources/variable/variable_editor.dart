part of '../resource_editor_registry.dart';

class _VariableEditor extends StatefulWidget {
  const _VariableEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_VariableEditor> createState() => _VariableEditorState();
}

class _VariableEditorState extends State<_VariableEditor> {
  final _formKey = GlobalKey<FormState>();
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
      text: _formatValue(variable.type, variable.defaultValue),
    );
    _currentValue = TextEditingController(
      text: _formatValue(variable.type, variable.currentValue),
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
    validate: () => _formKey.currentState!.validate(),
    fields: [
      Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _type,
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            TextFormField(
              controller: _defaultValue,
              decoration: const InputDecoration(labelText: 'Default value'),
              validator: _validateValue,
            ),
            TextFormField(
              controller: _currentValue,
              decoration: const InputDecoration(labelText: 'Current value'),
              validator: _validateValue,
            ),
          ],
        ),
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
          'type': _type.text.trim().toLowerCase(),
          'defaultValue': _readValue(
            _defaultValue.text,
            widget.resource.config['defaultValue'],
          ),
          'persistent': _persistent,
        },
        state: {
          ...widget.resource.state,
          'value': _readValue(
            _currentValue.text,
            VariableResource.fromResource(widget.resource).currentValue,
          ),
        },
      ),
    ),
  );

  Object? _readValue(String text, Object? original) {
    final type = _type.text.trim().toLowerCase();
    if (type == '${widget.resource.config['type']}'.trim().toLowerCase() &&
        text == _formatValue(type, original)) {
      return original;
    }
    final trimmed = text.trim();
    if (type == 'number' || type == 'duration') {
      final value = num.tryParse(trimmed);
      if (value == null || !value.isFinite) {
        throw const FormatException('Enter a valid number.');
      }
      return value;
    }
    if (type == 'boolean') {
      if (trimmed.toLowerCase() == 'true') return true;
      if (trimmed.toLowerCase() == 'false') return false;
      throw const FormatException('Enter true or false.');
    }
    if (_jsonType(type)) {
      final decoded = jsonDecode(trimmed);
      if ((type == 'object' || type == 'map') && decoded is! Map) {
        throw const FormatException('Enter a JSON object.');
      }
      if ((type == 'list' || type == 'array') && decoded is! List) {
        throw const FormatException('Enter a JSON list.');
      }
      return decoded;
    }
    return text;
  }

  String? _validateValue(String? value) {
    try {
      _readValue(value ?? '', null);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  static bool _jsonType(String type) => const {
    'json',
    'dynamic',
    'object',
    'map',
    'list',
    'array',
  }.contains(type.trim().toLowerCase());

  static String _formatValue(String type, Object? value) => value == null
      ? ''
      : _jsonType(type)
      ? jsonEncode(value)
      : '$value';
}
