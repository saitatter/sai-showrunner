import 'package:flutter/material.dart';

class DurationValueField extends StatefulWidget {
  const DurationValueField({
    super.key,
    required this.label,
    required this.initialSeconds,
    required this.onChanged,
  });

  final String label;
  final int initialSeconds;
  final ValueChanged<int> onChanged;

  @override
  State<DurationValueField> createState() => _DurationValueFieldState();
}

class _DurationValueFieldState extends State<DurationValueField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatDuration(widget.initialSeconds),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _controller,
    decoration: InputDecoration(labelText: widget.label, hintText: '1h 30m 0s'),
    keyboardType: TextInputType.text,
    onChanged: (value) {
      final seconds = parseDurationSeconds(value);
      if (seconds == null) return;
      widget.onChanged(seconds);
    },
  );
}

int? parseDurationSeconds(String input) {
  final value = input.trim().toLowerCase();
  if (value.isEmpty) return null;
  final plainSeconds = int.tryParse(value);
  if (plainSeconds != null && plainSeconds >= 0) return plainSeconds;
  final match = RegExp(
    r'^(?:(\d+)h)?\s*(?:(\d+)m)?\s*(?:(\d+)s)?$',
  ).firstMatch(value);
  if (match == null || match.group(0)!.trim().isEmpty) return null;
  final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
  final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
  if (minutes >= 60 || seconds >= 60) return null;
  return hours * 3600 + minutes * 60 + seconds;
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  if (hours > 0) return '${hours}h ${minutes}m ${remainder}s';
  if (minutes > 0) return '${minutes}m ${remainder}s';
  return '${remainder}s';
}
