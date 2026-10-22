import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import '../../../features/resources/color_field.dart';
import '../numeric_input_formatter.dart';
import 'style_values.dart';

class SchemaFieldRenderer extends StatelessWidget {
  const SchemaFieldRenderer({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final bool compact;
  final DartDataInputSchema schema;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (schema.kind == DartDataInputKind.color) {
      return ColorValueField(
        label: schema.label,
        bar: compact,
        initialValue: value?.toString() ?? '',
        onChanged: onChanged,
      );
    }
    if (schema.kind == DartDataInputKind.boolean) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(schema.label),
        value: value == true,
        onChanged: onChanged,
      );
    }
    if (schema.kind == DartDataInputKind.enumeration) {
      return DropdownButtonFormField<String>(
        initialValue: schema.options.contains(value?.toString())
            ? value.toString()
            : null,
        decoration: InputDecoration(labelText: schema.label),
        items: [
          for (final option in schema.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: onChanged,
      );
    }
    return _OverlayTextField(
      schema: schema,
      compact: compact,
      value: value,
      onChanged: (text) => onChanged(parseStyleScalar(schema, text)),
    );
  }
}

class _OverlayTextField extends StatefulWidget {
  const _OverlayTextField({
    required this.schema,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final bool compact;
  final DartDataInputSchema schema;
  final Object? value;
  final ValueChanged<String> onChanged;

  @override
  State<_OverlayTextField> createState() => _OverlayTextFieldState();
}

class _OverlayTextFieldState extends State<_OverlayTextField> {
  late final TextEditingController _controller;
  Object? _pendingValue;
  bool _hasPendingValue = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: styleText(widget.value));
  }

  @override
  void didUpdateWidget(covariant _OverlayTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownEcho = _hasPendingValue && widget.value == _pendingValue;
    _hasPendingValue = false;
    final identityChanged =
        oldWidget.schema.key != widget.schema.key ||
        oldWidget.schema.kind != widget.schema.kind;
    final next = styleText(widget.value);
    if ((identityChanged || (!ownEcho && oldWidget.value != widget.value)) &&
        next != _controller.text) {
      final selection = _controller.selection;
      _controller.value = TextEditingValue(
        text: next,
        selection: selection.isValid
            ? TextSelection(
                baseOffset: selection.baseOffset.clamp(0, next.length),
                extentOffset: selection.extentOffset.clamp(0, next.length),
              )
            : const TextSelection.collapsed(offset: -1),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit(String text) {
    _pendingValue = parseStyleScalar(widget.schema, text);
    _hasPendingValue = true;
    widget.onChanged(text);
  }

  Widget _stepButton(int step, IconData icon) => SizedBox(
    height: 16,
    child: IconButton(
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 14),
      onPressed: () {
        final current = num.tryParse(_controller.text) ?? 0;
        final next = current + step;
        if (widget.schema.key != 'offsetX' &&
            widget.schema.key != 'offsetY' &&
            next < 0) {
          return;
        }
        _controller.text = '$next';
        _emit('$next');
      },
    ),
  );

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines: widget.schema.kind == DartDataInputKind.multilineText ? 3 : 1,
    keyboardType: widget.schema.kind == DartDataInputKind.number
        ? TextInputType.number
        : TextInputType.text,
    inputFormatters: widget.schema.kind == DartDataInputKind.number
        ? const [NumericInputFormatter()]
        : null,
    obscureText: widget.schema.secret,
    style: widget.compact && widget.schema.key == 'fontFamily'
        ? TextStyle(fontFamily: _controller.text, fontSize: 16)
        : null,
    decoration: InputDecoration(
      labelText: widget.schema.label,
      suffixText:
          widget.compact && widget.schema.kind == DartDataInputKind.number
          ? 'px'
          : null,
      suffixIcon:
          widget.compact && widget.schema.kind == DartDataInputKind.number
          ? SizedBox(
              width: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stepButton(1, Icons.keyboard_arrow_up),
                  _stepButton(-1, Icons.keyboard_arrow_down),
                ],
              ),
            )
          : null,
    ),
    onChanged: _emit,
  );
}

Widget styleFieldRow(
  BuildContext context,
  List<DartDataInputSchema?> fields,
  dynamic value,
  ValueChanged<dynamic> onChanged, {
  bool compact = false,
}) {
  final values = styleMap(value);
  final valid = fields.whereType<DartDataInputSchema>().toList();
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < valid.length; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: SchemaFieldRenderer(
            schema: valid[index],
            compact: compact,
            value: values[valid[index].key ?? valid[index].label],
            onChanged: (next) => onChanged({
              ...values,
              valid[index].key ?? valid[index].label: next,
            }),
          ),
        ),
      ],
    ],
  );
}
