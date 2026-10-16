import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';

/// Keeps invalid drafts local; only valid values enter document history.
class GraphValueInput extends StatefulWidget {
  const GraphValueInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.onValidityChanged,
  });
  final ResolvedField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final ValueChanged<bool>? onValidityChanged;
  @override
  State<GraphValueInput> createState() => _GraphValueInputState();
}

class _GraphValueInputState extends State<GraphValueInput> {
  late final TextEditingController text;
  final focus = FocusNode();
  String? error;
  String encode(Object? value) => widget.field.kind == GraphFieldKind.string
      ? value?.toString() ?? ''
      : const JsonEncoder.withIndent('  ').convert(value);
  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: encode(widget.value));
  }

  @override
  void didUpdateWidget(GraphValueInput old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && old.value != widget.value) {
      text.text = encode(widget.value);
      error = null;
    }
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.field.kind == GraphFieldKind.boolean) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(widget.field.label),
        value: widget.value == true,
        onChanged: widget.onChanged,
      );
    }
    return TextField(
      controller: text,
      focusNode: focus,
      minLines: 1,
      maxLines: widget.field.kind == GraphFieldKind.json ? 8 : 1,
      decoration: InputDecoration(
        labelText: widget.field.label,
        errorText: error,
        isDense: true,
      ),
      onChanged: (draft) {
        try {
          final Object? value;
          if (widget.field.kind == GraphFieldKind.number) {
            final number = num.tryParse(draft);
            if (number == null || !number.isFinite) {
              throw const FormatException('Enter a finite number');
            }
            value = number;
          } else if (widget.field.kind == GraphFieldKind.json ||
              widget.field.kind == GraphFieldKind.custom) {
            value = jsonDecode(draft);
          } else {
            value = draft;
          }
          setState(() => error = null);
          widget.onChanged(value);
          widget.onValidityChanged?.call(true);
        } on FormatException catch (exception) {
          setState(() => error = exception.message);
          widget.onValidityChanged?.call(false);
        }
      },
    );
  }
}
