import 'dart:convert';

import 'package:flutter/material.dart';

import '../../schema/data_input.dart';

export '../../schema/data_input.dart';

import '../../features/resources/color_field.dart';
import '../../features/resources/duration_field.dart';
import '../../plugins/iot/ui/light_color_input.dart';
import '../../plugins/input/ui/key_combo_input.dart';
import '../../plugins/input/ui/keyboard_key_input.dart';
import '../../plugins/obs/ui/obs_transform_input.dart';
import 'overlay_style_inputs.dart';

class DartDataInput extends StatefulWidget {
  const DartDataInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
    this.templateSuggestions = const <String>[],
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final List<String> templateSuggestions;

  @override
  State<DartDataInput> createState() => _DartDataInputState();
}

class _DartDataInputState extends State<DartDataInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue(widget.value));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DartDataInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _displayValue(widget.value);
    if (next != _controller.text) {
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.schema.editor != null) {
      return OverlayStyleInput(
        schema: widget.schema,
        value: widget.value,
        onChanged: widget.onChanged,
      );
    }

    if (widget.schema.template &&
        (widget.schema.kind == DartDataInputKind.text ||
            widget.schema.kind == DartDataInputKind.multilineText ||
            widget.schema.kind == DartDataInputKind.number)) {
      return _TemplateDataInput(
        schema: widget.schema,
        value: widget.value,
        suggestions: widget.templateSuggestions,
        onChanged: widget.onChanged,
      );
    }

    return switch (widget.schema.kind) {
      DartDataInputKind.boolean => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(widget.schema.label),
        value: widget.value == true,
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.enumeration => DropdownButtonFormField<String>(
        initialValue: widget.schema.options.contains(widget.value?.toString())
            ? widget.value.toString()
            : null,
        decoration: InputDecoration(labelText: widget.schema.label),
        items: [
          for (final option in widget.schema.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.color => ColorValueField(
        label: widget.schema.label,
        initialValue: _displayValue(widget.value),
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.duration => DurationValueField(
        label: widget.schema.label,
        initialSeconds: _numberValue(widget.value).round(),
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.lightColor => LightColorInput(
        label: widget.schema.label,
        value: widget.value?.toString(),
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.obsTransform => ObsTransformInput(
        label: widget.schema.label,
        value: widget.value is Map
            ? Map<String, dynamic>.from(widget.value as Map)
            : null,
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.keyboardKey => KeyboardKeyInput(
        label: widget.schema.label,
        value: widget.value?.toString(),
        requiredValue: widget.schema.required,
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.keyCombo => KeyComboInput(
        label: widget.schema.label,
        value: widget.value is List
            ? (widget.value as List).map((item) => item.toString()).toList()
            : null,
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.array => _ArrayInput(
        schema: widget.schema,
        value: widget.value,
        templateSuggestions: widget.templateSuggestions,
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.object => _ObjectInput(
        schema: widget.schema,
        value: widget.value,
        templateSuggestions: widget.templateSuggestions,
        onChanged: widget.onChanged,
      ),
      DartDataInputKind.resource =>
        widget.schema.options.isEmpty
            ? TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: widget.schema.label,
                  hintText: widget.schema.resourceType == null
                      ? 'Resource ID'
                      : '${widget.schema.resourceType!.value} ID',
                ),
                onChanged: (text) => widget.onChanged(text.trim()),
              )
            : DropdownButtonFormField<String>(
                initialValue:
                    widget.schema.options.contains(widget.value?.toString())
                    ? widget.value.toString()
                    : null,
                decoration: InputDecoration(labelText: widget.schema.label),
                items: [
                  for (final option in widget.schema.options)
                    DropdownMenuItem(value: option, child: Text(option)),
                  if (widget.value?.toString().trim().isNotEmpty == true &&
                      !widget.schema.options.contains(widget.value.toString()))
                    DropdownMenuItem(
                      value: widget.value.toString(),
                      child: Text('${widget.value} (stored value)'),
                    ),
                ],
                onChanged: widget.onChanged,
              ),
      _ => TextField(
        controller: _controller,
        obscureText: widget.schema.secret,
        maxLines:
            widget.schema.multiline ||
                widget.schema.kind == DartDataInputKind.multilineText ||
                widget.schema.kind == DartDataInputKind.object
            ? 4
            : 1,
        keyboardType: widget.schema.kind == DartDataInputKind.number
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: widget.schema.label,
          suffixIcon: widget.schema.kind == DartDataInputKind.filePath
              ? const Icon(Icons.folder_open_outlined)
              : null,
        ),
        onChanged: (text) =>
            widget.onChanged(_parseValue(widget.schema.kind, text)),
      ),
    };
  }
}

class _ObjectInput extends StatelessWidget {
  const _ObjectInput({
    required this.schema,
    required this.value,
    required this.templateSuggestions,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final List<String> templateSuggestions;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = value is Map
        ? Map<String, dynamic>.from(value as Map)
        : <String, dynamic>{};
    if (schema.fields.isEmpty) {
      return _JsonObjectInput(
        label: schema.label,
        value: value,
        onChanged: onChanged,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (schema.label.isNotEmpty)
          Text(schema.label, style: Theme.of(context).textTheme.titleSmall),
        for (final field in schema.fields)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DartDataInput(
              key: ValueKey(field.key ?? field.label),
              schema: field,
              value: values[field.key ?? field.label],
              templateSuggestions: templateSuggestions,
              onChanged: (next) =>
                  onChanged({...values, field.key ?? field.label: next}),
            ),
          ),
      ],
    );
  }
}

class _JsonObjectInput extends StatefulWidget {
  const _JsonObjectInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_JsonObjectInput> createState() => _JsonObjectInputState();
}

class _JsonObjectInputState extends State<_JsonObjectInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue(widget.value));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    minLines: 4,
    maxLines: 8,
    decoration: InputDecoration(
      labelText: widget.label,
      alignLabelWithHint: true,
      border: const OutlineInputBorder(),
    ),
    onChanged: (text) =>
        widget.onChanged(_parseValue(DartDataInputKind.object, text)),
  );
}

class _ArrayInput extends StatelessWidget {
  const _ArrayInput({
    required this.schema,
    required this.value,
    required this.templateSuggestions,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final List<String> templateSuggestions;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = value is List
        ? List<dynamic>.from(value as List)
        : <dynamic>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                schema.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Add item',
              onPressed: () => onChanged([
                ...items,
                schema.itemSchema != null
                    ? constructDartDataInputDefault(schema.itemSchema!)
                    : schema.itemKind == DartDataInputKind.object
                    ? <String, dynamic>{}
                    : '',
              ]),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        for (var index = 0; index < items.length; index++)
          Row(
            children: [
              Expanded(
                child: schema.itemSchema == null
                    ? TextFormField(
                        initialValue: _displayValue(items[index]),
                        decoration: InputDecoration(
                          labelText: '${schema.label} ${index + 1}',
                          suffixIcon:
                              schema.itemKind == DartDataInputKind.filePath
                              ? const Icon(Icons.folder_open_outlined)
                              : null,
                        ),
                        onChanged: (next) {
                          final updated = [...items];
                          updated[index] = _parseValue(schema.itemKind, next);
                          onChanged(updated);
                        },
                      )
                    : DartDataInput(
                        key: ValueKey('${schema.label}-$index'),
                        schema: schema.itemSchema!,
                        value: items[index],
                        templateSuggestions: templateSuggestions,
                        onChanged: (next) {
                          final updated = [...items];
                          updated[index] = next;
                          onChanged(updated);
                        },
                      ),
              ),
              IconButton(
                tooltip: 'Duplicate item',
                onPressed: () {
                  final updated = [...items]..insert(index + 1, items[index]);
                  onChanged(updated);
                },
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Delete item',
                onPressed: () {
                  final updated = [...items]..removeAt(index);
                  onChanged(updated);
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
      ],
    );
  }
}

class _TemplateDataInput extends StatefulWidget {
  const _TemplateDataInput({
    required this.schema,
    required this.value,
    required this.suggestions,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final List<String> suggestions;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_TemplateDataInput> createState() => _TemplateDataInputState();
}

class _TemplateDataInputState extends State<_TemplateDataInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue(widget.value));
  }

  @override
  void didUpdateWidget(covariant _TemplateDataInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _displayValue(widget.value);
    if (next != _controller.text) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines:
        widget.schema.multiline ||
            widget.schema.kind == DartDataInputKind.multilineText
        ? 4
        : 1,
    decoration: InputDecoration(
      labelText: widget.schema.label,
      alignLabelWithHint:
          widget.schema.multiline ||
          widget.schema.kind == DartDataInputKind.multilineText,
      suffixIcon: IconButton(
        tooltip: 'Insert variable',
        onPressed: _showSuggestions,
        icon: const Icon(Icons.data_object),
      ),
    ),
    onChanged: (text) => widget.onChanged(_valueFor(text)),
  );

  dynamic _valueFor(String text) {
    if (widget.schema.kind == DartDataInputKind.number &&
        !text.contains('{{')) {
      return num.tryParse(text.trim()) ?? 0;
    }
    return text;
  }

  Future<void> _showSuggestions() async {
    final suggestion = await showDialog<String>(
      context: context,
      builder: (context) =>
          _TemplateSuggestionDialog(suggestions: widget.suggestions),
    );
    if (!mounted || suggestion == null) return;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : start;
    final insertion = '{{ $suggestion }}';
    final value = _controller.text.replaceRange(start, end, insertion);
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    widget.onChanged(_valueFor(value));
  }
}

class _TemplateSuggestionDialog extends StatefulWidget {
  const _TemplateSuggestionDialog({required this.suggestions});

  final List<String> suggestions;

  @override
  State<_TemplateSuggestionDialog> createState() =>
      _TemplateSuggestionDialogState();
}

class _TemplateSuggestionDialogState extends State<_TemplateSuggestionDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final suggestions = widget.suggestions
        .where((value) => value.toLowerCase().contains(query))
        .toList(growable: false);
    return AlertDialog(
      title: const Text('Insert variable'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search variables and state',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: suggestions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No matching variables.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: suggestions.length,
                      itemBuilder: (context, index) {
                        final value = suggestions[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.data_object),
                          title: Text(value),
                          subtitle: Text('{{ $value }}'),
                          onTap: () => Navigator.pop(context, value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

String _displayValue(dynamic value) {
  if (value is Map) return const JsonEncoder.withIndent('  ').convert(value);
  if (value is List) return value.join(', ');
  return value?.toString() ?? '';
}

double _numberValue(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

dynamic _parseValue(DartDataInputKind kind, String value) {
  final trimmed = value.trim();
  switch (kind) {
    case DartDataInputKind.number:
      return num.tryParse(trimmed) ?? 0;
    case DartDataInputKind.array:
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) return decoded;
      } on FormatException {
        // Fall through to the convenient comma-separated form.
      }
      return trimmed
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    case DartDataInputKind.object:
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        // Keep invalid JSON visible for the user to correct.
      }
      return trimmed;
    case DartDataInputKind.filePath:
    case DartDataInputKind.multilineText:
    case DartDataInputKind.resource:
    case DartDataInputKind.text:
    case DartDataInputKind.enumeration:
    case DartDataInputKind.color:
    case DartDataInputKind.duration:
    case DartDataInputKind.boolean:
    case DartDataInputKind.keyboardKey:
    case DartDataInputKind.keyCombo:
    case DartDataInputKind.lightColor:
    case DartDataInputKind.obsTransform:
      return value;
  }
}
