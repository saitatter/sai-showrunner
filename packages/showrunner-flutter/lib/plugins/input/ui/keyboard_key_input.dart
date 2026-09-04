import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keyboard.dart';

final class KeyboardKeyInput extends StatefulWidget {
  const KeyboardKeyInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.requiredValue = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool requiredValue;

  @override
  State<KeyboardKeyInput> createState() => _KeyboardKeyInputState();
}

class _KeyboardKeyInputState extends State<KeyboardKeyInput> {
  late final FocusNode _focusNode;
  var _capturing = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'keyboard-key-capture');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    onKeyEvent: _handleKeyEvent,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: legacyKeyboardKeyNames.contains(widget.value)
                ? widget.value
                : null,
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: _capturing ? 'Press a key' : null,
            ),
            items: [
              for (final key in legacyKeyboardKeyNames)
                DropdownMenuItem(
                  value: key,
                  child: Text(keyboardKeyDisplayName(key)),
                ),
            ],
            onChanged: (value) {
              if (_capturing) setState(() => _capturing = false);
              widget.onChanged(value);
            },
          ),
        ),
        IconButton(
          tooltip: _capturing ? 'Stop key capture' : 'Capture key',
          onPressed: _beginCapture,
          icon: Icon(_capturing ? Icons.stop : Icons.keyboard),
        ),
      ],
    ),
  );

  void _beginCapture() {
    setState(() => _capturing = true);
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_capturing) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      final key = keyboardKeyNameForLogicalKey(event.logicalKey);
      if (key != null) {
        widget.onChanged(key);
        setState(() => _capturing = false);
      }
    }
    return KeyEventResult.handled;
  }
}