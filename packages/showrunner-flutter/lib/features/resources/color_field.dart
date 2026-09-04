import 'package:flutter/material.dart';

class ColorValueField extends StatefulWidget {
  const ColorValueField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<ColorValueField> createState() => _ColorValueFieldState();
}

class _ColorValueFieldState extends State<ColorValueField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: _ColorSwatch(value: _controller.text),
        ),
        suffixIcon: IconButton(
          tooltip: 'Choose color',
          icon: const Icon(Icons.palette_outlined),
          onPressed: _chooseColor,
        ),
      ),
      onChanged: (value) {
        widget.onChanged(value);
        setState(() {});
      },
    ),
  );

  Future<void> _chooseColor() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _colorChoice(context, 'transparent'),
            for (final value in _palette) _colorChoice(context, value),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _controller.value = TextEditingValue(text: selected);
    widget.onChanged(selected);
    setState(() {});
  }

  Widget _colorChoice(BuildContext context, String value) => Tooltip(
    message: value,
    child: InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: _ColorSwatch(value: value, size: 32),
      ),
    ),
  );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.value, this.size = 20});

  final String value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(value);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: color == null ? const Icon(Icons.block, size: 14) : null,
    );
  }
}

const _palette = <String>[
  '#ffffff',
  '#000000',
  '#ef4444',
  '#f97316',
  '#eab308',
  '#22c55e',
  '#06b6d4',
  '#3b82f6',
  '#8b5cf6',
  '#ec4899',
];

Color? _parseColor(String value) {
  if (value.toLowerCase() == 'transparent') return null;
  final hex = value.replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('ff$hex', radix: 16));
}
