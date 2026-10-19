import '../../components/data_inputs/numeric_input_formatter.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// CSS hexadecimal colors use RGBA ordering when an alpha channel is present.
Color? parseCssColor(String value) {
  if (value.toLowerCase() == 'transparent') return Colors.transparent;
  final hex = value.replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
    return null;
  }
  final number = int.parse(hex, radix: 16);
  return hex.length == 6
      ? Color(0xff000000 | number)
      : Color(((number & 255) << 24) | (number >> 8));
}

String cssColorHex(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xffffff).toRadixString(16).padLeft(6, '0');
  final alpha = (argb >> 24) & 255;
  return '#$rgb${alpha == 255 ? '' : alpha.toRadixString(16).padLeft(2, '0')}';
}

class ShowRunnerColorPicker extends StatefulWidget {
  const ShowRunnerColorPicker({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.onPaletteSelected,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onPaletteSelected;

  @override
  State<ShowRunnerColorPicker> createState() => _ShowRunnerColorPickerState();
}

class _ShowRunnerColorPickerState extends State<ShowRunnerColorPicker> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  Color get _color => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(
      parseCssColor(widget.initialValue) ?? Colors.white,
    );
    _hex = TextEditingController(text: cssColorHex(_color).substring(1));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _change(HSVColor next, {bool updateHex = true}) {
    setState(() => _hsv = next);
    final value = cssColorHex(_color);
    if (updateHex) _hex.text = value.substring(1).toUpperCase();
    widget.onChanged(value);
  }

  void _rgb(int channel, double value) {
    final argb = _color.toARGB32();
    final shift = 16 - channel * 8;
    final next = (argb & ~(255 << shift)) | (value.round() << shift);
    _change(HSVColor.fromColor(Color(next)));
  }

  @override
  Widget build(BuildContext context) {
    final argb = _color.toARGB32();
    final rgb = [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255];
    final opaque = _color.withValues(alpha: 1);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    AspectRatio(
                      aspectRatio: 1,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          void select(Offset position) {
                            final radius = constraints.maxWidth / 2;
                            final delta = position - Offset(radius, radius);
                            final hue =
                                (math.atan2(delta.dy, delta.dx) *
                                        180 /
                                        math.pi +
                                    90 +
                                    360) %
                                360;
                            _change(
                              _hsv
                                  .withHue(hue)
                                  .withSaturation(
                                    (delta.distance / radius).clamp(0, 1),
                                  ),
                            );
                          }

                          return GestureDetector(
                            key: const ValueKey('color-wheel'),
                            onTapDown: (event) => select(event.localPosition),
                            onPanStart: (event) => select(event.localPosition),
                            onPanUpdate: (event) => select(event.localPosition),
                            child: CustomPaint(painter: _WheelPainter(_hsv)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('color-hex'),
                      controller: _hex,
                      decoration: const InputDecoration(labelText: 'Hex color'),
                      onChanged: (value) {
                        final color = parseCssColor(value);
                        if (color != null) {
                          _change(HSVColor.fromColor(color), updateHex: false);
                        }
                      },
                      onEditingComplete: () {
                        _hex.text = cssColorHex(
                          _color,
                        ).substring(1).toUpperCase();
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RGB', style: TextStyle(fontSize: 12)),
                    for (var channel = 0; channel < 3; channel++)
                      _ChannelRow(
                        label: ['R', 'G', 'B'][channel],
                        value: rgb[channel].toDouble(),
                        max: 255,
                        colors: [
                          Color.fromARGB(
                            255,
                            channel == 0 ? 0 : rgb[0],
                            channel == 1 ? 0 : rgb[1],
                            channel == 2 ? 0 : rgb[2],
                          ),
                          Color.fromARGB(
                            255,
                            channel == 0 ? 255 : rgb[0],
                            channel == 1 ? 255 : rgb[1],
                            channel == 2 ? 255 : rgb[2],
                          ),
                        ],
                        onChanged: (value) => _rgb(channel, value),
                      ),
                    const Text('HSV', style: TextStyle(fontSize: 12)),
                    _ChannelRow(
                      label: 'H',
                      value: _hsv.hue,
                      max: 360,
                      colors: [
                        for (var hue = 0; hue <= 360; hue += 60)
                          HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor(),
                      ],
                      onChanged: (value) => _change(_hsv.withHue(value % 360)),
                    ),
                    _ChannelRow(
                      label: 'S',
                      value: _hsv.saturation * 100,
                      max: 100,
                      colors: [
                        _hsv.withAlpha(1).withSaturation(0).toColor(),
                        _hsv.withAlpha(1).withSaturation(1).toColor(),
                      ],
                      onChanged: (value) =>
                          _change(_hsv.withSaturation(value / 100)),
                    ),
                    _ChannelRow(
                      label: 'V',
                      value: _hsv.value * 100,
                      max: 100,
                      colors: [
                        Colors.black,
                        _hsv.withAlpha(1).withValue(1).toColor(),
                      ],
                      onChanged: (value) =>
                          _change(_hsv.withValue(value / 100)),
                    ),
                    _ChannelRow(
                      label: 'A',
                      value: _hsv.alpha * 255,
                      max: 255,
                      colors: [opaque.withValues(alpha: 0), opaque],
                      checker: true,
                      onChanged: (value) =>
                          _change(_hsv.withAlpha(value / 255)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            children: [
              for (final hex in const [
                'transparent',
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
              ])
                Tooltip(
                  message: hex,
                  child: InkWell(
                    onTap: () => widget.onPaletteSelected(hex),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CustomPaint(
                        painter: _GradientPainter([
                          parseCssColor(hex)!,
                          parseCssColor(hex)!,
                        ], checker: true),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.label,
    required this.value,
    required this.max,
    required this.colors,
    required this.onChanged,
    this.checker = false,
  });
  final String label;
  final double value;
  final double max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final bool checker;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                void select(Offset position) => onChanged(
                  (position.dx / constraints.maxWidth).clamp(0, 1) * max,
                );
                return GestureDetector(
                  key: ValueKey('color-slider-$label'),
                  onTapDown: (event) => select(event.localPosition),
                  onPanStart: (event) => select(event.localPosition),
                  onPanUpdate: (event) => select(event.localPosition),
                  child: CustomPaint(
                    painter: _GradientPainter(
                      colors,
                      checker: checker,
                      position: value / max,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 70,
            child: _ChannelNumber(
              label: label,
              value: value.round(),
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChannelNumber extends StatefulWidget {
  const _ChannelNumber({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  State<_ChannelNumber> createState() => _ChannelNumberState();
}

class _ChannelNumberState extends State<_ChannelNumber> {
  late final _controller = TextEditingController(text: '${widget.value}');
  @override
  void didUpdateWidget(_ChannelNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: ValueKey('color-channel-${widget.label}'),
    controller: _controller,
    inputFormatters: const [
      NumericInputFormatter(decimal: false, signed: false),
    ],
    keyboardType: TextInputType.number,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      contentPadding: const EdgeInsets.only(left: 8),
      suffixIconConstraints: const BoxConstraints.tightFor(
        width: 18,
        height: 28,
      ),
      suffixIcon: Column(
        children: [
          for (final direction in [1, -1])
            Expanded(
              child: InkWell(
                onTap: () => widget.onChanged(
                  (widget.value + direction).clamp(0, widget.max).toDouble(),
                ),
                child: Icon(
                  direction == 1
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    ),
    onChanged: (text) {
      final value = double.tryParse(text);
      if (value != null &&
          value.isFinite &&
          value >= 0 &&
          value <= widget.max) {
        widget.onChanged(value);
      }
    },
  );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          transform: GradientRotation(-math.pi / 2),
          colors: [
            Color(0xffff0000),
            Color(0xffffff00),
            Color(0xff00ff00),
            Color(0xff00ffff),
            Color(0xff0000ff),
            Color(0xffff00ff),
            Color(0xffff0000),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00ffffff)],
        ).createShader(rect),
    );
    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }
    final angle = (hsv.hue - 90) * math.pi / 180;
    final marker =
        center +
        Offset(math.cos(angle), math.sin(angle)) * radius * hsv.saturation;
    canvas.drawCircle(
      marker,
      5,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      marker,
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => hsv != oldDelegate.hsv;
}

class _GradientPainter extends CustomPainter {
  const _GradientPainter(this.colors, {this.checker = false, this.position});
  final List<Color> colors;
  final bool checker;
  final double? position;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    if (checker) {
      for (var y = 0.0; y < size.height; y += 7) {
        for (var x = 0.0; x < size.width; x += 7) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, 7, 7),
            Paint()
              ..color = ((x / 7).floor() + (y / 7).floor()).isEven
                  ? const Color(0xff888888)
                  : const Color(0xff444444),
          );
        }
      }
    }
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
    if (position != null) {
      final marker = Offset(
        (position! * size.width).clamp(4, math.max(4, size.width - 4)),
        size.height / 2,
      );
      canvas.drawCircle(
        marker,
        4,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
        marker,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GradientPainter oldDelegate) => true;
}
