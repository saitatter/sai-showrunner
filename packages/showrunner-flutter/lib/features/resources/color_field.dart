import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'color_picker.dart';

class ColorValueField extends StatefulWidget {
  const ColorValueField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.bar = false,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool bar;

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
  void didUpdateWidget(ColorValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) => widget.bar
      ? InkWell(
          onTap: _chooseColor,
          child: InputDecorator(
            decoration: InputDecoration(labelText: widget.label),
            child: SizedBox(
              height: 24,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _ColorSwatch(value: _controller.text),
              ),
            ),
          ),
        )
      : SizedBox(
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
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final initialValue = _controller.text;
    void update(String value) {
      if (!mounted) return;
      _controller.text = value;
      widget.onChanged(value);
      setState(() {});
    }

    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(402.0, constraints.maxWidth - 24);
          final left = anchor.left.clamp(
            12.0,
            math.max(12.0, constraints.maxWidth - width - 12),
          );
          final top = anchor.bottom.clamp(
            12.0,
            math.max(12.0, constraints.maxHeight - 330),
          );
          return Stack(
            children: [
              Positioned(
                left: left.toDouble(),
                top: top.toDouble(),
                width: width,
                child: Material(
                  key: const ValueKey('color-picker-popover'),
                  color: const Color(0xff202020),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                    side: const BorderSide(color: Color(0xff555555)),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      inputDecorationTheme: InputDecorationTheme(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xff121212),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: Color(0xff555555),
                          ),
                        ),
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: math.max(
                          1,
                          constraints.maxHeight - top - 12,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: ShowRunnerColorPicker(
                          initialValue: initialValue,
                          onChanged: update,
                          onPaletteSelected: (value) =>
                              Navigator.of(context).pop(value),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    update(selected);
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.value});

  final String value;
  final double size = 20;

  @override
  Widget build(BuildContext context) {
    final color = parseCssColor(value);
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
