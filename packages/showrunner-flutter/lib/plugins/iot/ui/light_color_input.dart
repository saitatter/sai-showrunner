import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../light_color.dart';

final class LightColorInput extends StatefulWidget {
  const LightColorInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<LightColorInput> createState() => _LightColorInputState();
}

class _LightColorInputState extends State<LightColorInput> {
  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: widget.label,
      suffixIcon: IconButton(
        tooltip: 'Choose light color',
        onPressed: _openPicker,
        icon: const Icon(Icons.colorize),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: lightColorPreview(widget.value),
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(widget.value?.trim().isNotEmpty == true
              ? widget.value!
              : 'Not set'),
        ),
      ],
    ),
  );

  Future<void> _openPicker() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _LightColorDialog(initialValue: widget.value),
    );
    if (value != null && mounted) widget.onChanged(value);
  }
}

class _LightColorDialog extends StatefulWidget {
  const _LightColorDialog({required this.initialValue});

  final String? initialValue;

  @override
  State<_LightColorDialog> createState() => _LightColorDialogState();
}

class _LightColorDialogState extends State<_LightColorDialog> {
  late String? _value;
  var _mode = 'rgb';

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialValue == null ? 'Choose light color' : 'Edit light color'),
    content: SizedBox(
      width: 360,
      height: 250,
      child: Column(
        children: [
          ToggleButtons(
            isSelected: [_mode == 'rgb', _mode == 'cct'],
            onPressed: (index) => setState(() => _mode = index == 0 ? 'rgb' : 'cct'),
            children: const [Text('RGB'), Text('CCT')],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _mode == 'rgb'
                      ? LightColorWheel(value: _value, onChanged: _update)
                      : LightTemperatureSlider(value: _value, onChanged: _update),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 44,
                  child: LightBrightnessSlider(value: _value, onChanged: _update),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_value),
        child: const Text('Apply'),
      ),
    ],
  );

  void _update(String value) => setState(() => _value = value);
}

final class LightColorWheel extends StatelessWidget {
  const LightColorWheel({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _update(details.localPosition, size),
        onPanUpdate: (details) => _update(details.localPosition, size),
        child: CustomPaint(
          size: size,
          painter: _LightColorWheelPainter(value),
          child: const SizedBox.expand(),
        ),
      );
    },
  );

  void _update(Offset position, Size size) {
    final diameter = math.min(size.width, size.height);
    if (diameter <= 0) return;
    final radius = diameter / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final delta = position - center;
    final distance = math.min(delta.distance, radius);
    final angle = math.atan2(delta.dy, delta.dx);
    final hue = (90 + angle * 180 / math.pi + 360) % 360;
    onChanged(
      serializeLightColor(
        lightColorForHueSaturation(value, hue, distance / radius * 100),
      ),
    );
  }
}

final class LightTemperatureSlider extends StatelessWidget {
  const LightTemperatureSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (details) => _update(details.localPosition, context.size),
    onPanUpdate: (details) => _update(details.localPosition, context.size),
    child: CustomPaint(
      painter: _LightTemperaturePainter(value),
      child: const SizedBox.expand(),
    ),
  );

  void _update(Offset position, Size? size) {
    final height = size?.height ?? 0;
    if (height <= 0) return;
    final fraction = (position.dy / height).clamp(0.0, 1.0);
    final kelvin = lightColorMinKelvin +
        fraction * (lightColorMaxKelvin - lightColorMinKelvin);
    onChanged(serializeLightColor(lightColorForKelvin(value, kelvin)));
  }
}

final class LightBrightnessSlider extends StatelessWidget {
  const LightBrightnessSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (details) => _update(details.localPosition, context.size),
    onPanUpdate: (details) => _update(details.localPosition, context.size),
    child: CustomPaint(
      painter: _LightBrightnessPainter(value),
      child: const SizedBox.expand(),
    ),
  );

  void _update(Offset position, Size? size) {
    final height = size?.height ?? 0;
    if (height <= 0) return;
    final fraction = (position.dy / height).clamp(0.0, 1.0);
    onChanged(serializeLightColor(lightColorForBrightness(value, (1 - fraction) * 100)));
  }
}

class _LightColorWheelPainter extends CustomPainter {
  _LightColorWheelPainter(this.value);

  final String? value;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = math.min(size.width, size.height);
    final radius = diameter / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(bounds));
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Color(0xffff00ff),
            Colors.red,
          ],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Colors.transparent],
        ).createShader(bounds),
    );
    canvas.restore();

    final parsed = parseLightColor(value);
    final hue = parsed?.isKelvin == false ? parsed!.hue! : 0;
    final saturation = parsed?.isKelvin == false ? parsed!.saturation! : 100;
    final angle = (hue - 90) * math.pi / 180;
    final point = center + Offset(
      math.cos(angle) * radius * saturation / 100,
      math.sin(angle) * radius * saturation / 100,
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.drawCircle(
      point,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(covariant _LightColorWheelPainter oldDelegate) =>
      oldDelegate.value != value;
}

class _LightTemperaturePainter extends CustomPainter {
  _LightTemperaturePainter(this.value);

  final String? value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = [
      for (var index = 0; index <= 10; index++)
        lightColorPreview(
          serializeLightColor(
            LightColorValue.kelvin(
              kelvin: lightColorMinKelvin +
                  index / 10 * (lightColorMaxKelvin - lightColorMinKelvin),
              brightness: 100,
            ),
          ),
        ),
    ];
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(rect),
    );
    final parsed = parseLightColor(value);
    final kelvin = parsed?.isKelvin == true
        ? parsed!.kelvin!
        : (lightColorMinKelvin + lightColorMaxKelvin) / 2;
    final fraction = (kelvin - lightColorMinKelvin) /
        (lightColorMaxKelvin - lightColorMinKelvin);
    _drawSliderDot(canvas, Offset(size.width / 2, size.height * fraction));
  }

  @override
  bool shouldRepaint(covariant _LightTemperaturePainter oldDelegate) =>
      oldDelegate.value != value;
}

class _LightBrightnessPainter extends CustomPainter {
  _LightBrightnessPainter(this.value);

  final String? value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fullValue = lightColorForBrightness(value, 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lightColorPreview(serializeLightColor(fullValue)), Colors.black],
        ).createShader(rect),
    );
    final brightness = parseLightColor(value)?.brightness ?? 100;
    _drawSliderDot(canvas, Offset(size.width / 2, size.height * (1 - brightness / 100)));
  }

  @override
  bool shouldRepaint(covariant _LightBrightnessPainter oldDelegate) =>
      oldDelegate.value != value;
}

void _drawSliderDot(Canvas canvas, Offset point) {
  canvas.drawCircle(
    point,
    6,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white,
  );
  canvas.drawCircle(
    point,
    7,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black54,
  );
}