import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keyboard.dart';

final class KeyComboInput extends StatefulWidget {
  const KeyComboInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<String>? value;
  final ValueChanged<List<String>> onChanged;

  @override
  State<KeyComboInput> createState() => _KeyComboInputState();
}

class _KeyComboInputState extends State<KeyComboInput> {
  late final FocusNode _focusNode;
  var _capturing = false;
  var _captured = <String>[];

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'key-combo-capture');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value ?? const <String>[];
    final display = value.isEmpty
        ? (_capturing ? 'Press the keys' : 'No keys selected')
        : keyboardComboDisplayName(value);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: _capturing ? 'Release a key to finish' : null,
              ),
              child: Text(display),
            ),
          ),
          if (value.isNotEmpty)
            IconButton(
              tooltip: 'Clear keys',
              onPressed: () => widget.onChanged(const <String>[]),
              icon: const Icon(Icons.clear),
            ),
          IconButton(
            tooltip: _capturing ? 'Stop key capture' : 'Capture key combination',
            onPressed: _beginCapture,
            icon: Icon(_capturing ? Icons.stop : Icons.keyboard),
          ),
        ],
      ),
    );
  }

  void _beginCapture() {
    setState(() {
      _capturing = true;
      _captured = <String>[];
    });
    widget.onChanged(const <String>[]);
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_capturing) return KeyEventResult.ignored;
    final key = keyboardKeyNameForLogicalKey(event.logicalKey);
    if (key == null) return KeyEventResult.handled;
    if (event is KeyDownEvent) {
      final next = appendKeyboardKey(_captured, key);
      if (next.length != _captured.length) {
        setState(() => _captured = next);
        widget.onChanged(next);
      }
    } else if (event is KeyUpEvent) {
      setState(() => _capturing = false);
    }
    return KeyEventResult.handled;
  }
}