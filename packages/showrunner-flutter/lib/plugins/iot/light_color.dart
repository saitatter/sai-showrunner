import 'dart:math' as math;

import 'package:flutter/material.dart';

const lightColorMinKelvin = 2000.0;
const lightColorMaxKelvin = 6535.0;

final class LightColorValue {
  const LightColorValue.hsb({
    required this.hue,
    required this.saturation,
    required this.brightness,
  }) : kelvin = null;

  const LightColorValue.kelvin({
    required this.kelvin,
    required this.brightness,
  }) : hue = null,
       saturation = null;

  final double? hue;
  final double? saturation;
  final double? kelvin;
  final double brightness;

  bool get isKelvin => kelvin != null;
}

LightColorValue? parseLightColor(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  final isHsb = text.startsWith('hsb(') && text.endsWith(')');
  final isKelvin = text.startsWith('kb(') && text.endsWith(')');
  if (!isHsb && !isKelvin) return null;
  final prefixLength = isHsb ? 4 : 3;
  final parts = text.substring(prefixLength, text.length - 1).split(',');
  final values = parts.map((part) => double.tryParse(part.trim())).toList();
  if (values.any((value) => value == null || !value.isFinite)) return null;
  if (isHsb && values.length == 3) {
    return LightColorValue.hsb(
      hue: values[0]!,
      saturation: values[1]!,
      brightness: values[2]!,
    );
  }
  if (isKelvin && values.length == 2) {
    return LightColorValue.kelvin(
      kelvin: values[0]!,
      brightness: values[1]!,
    );
  }
  return null;
}

String serializeLightColor(LightColorValue value) {
  if (value.isKelvin) {
    return 'kb(${_formatNumber(value.kelvin!)}, '
        '${_formatNumber(value.brightness)})';
  }
  return 'hsb(${_formatNumber(value.hue!)}, '
      '${_formatNumber(value.saturation!)}, '
      '${_formatNumber(value.brightness)})';
}

LightColorValue lightColorForHueSaturation(
  String? value,
  double hue,
  double saturation,
) {
  final current = parseLightColor(value);
  return LightColorValue.hsb(
    hue: _wrapHue(hue),
    saturation: _clamp(saturation, 0, 100),
    brightness: _clamp(current?.brightness ?? 100, 0, 100),
  );
}

LightColorValue lightColorForKelvin(String? value, double kelvin) {
  final current = parseLightColor(value);
  return LightColorValue.kelvin(
    kelvin: _clamp(kelvin, lightColorMinKelvin, lightColorMaxKelvin),
    brightness: _clamp(current?.brightness ?? 100, 0, 100),
  );
}

LightColorValue lightColorForBrightness(String? value, double brightness) {
  final current = parseLightColor(value);
  if (current?.isKelvin == true) {
    return LightColorValue.kelvin(
      kelvin: _clamp(current!.kelvin!, lightColorMinKelvin, lightColorMaxKelvin),
      brightness: _clamp(brightness, 0, 100),
    );
  }
  return LightColorValue.hsb(
    hue: _wrapHue(current?.hue ?? 0),
    saturation: _clamp(current?.saturation ?? 100, 0, 100),
    brightness: _clamp(brightness, 0, 100),
  );
}

Color lightColorPreview(String? value) {
  final parsed = parseLightColor(value);
  if (parsed == null) return Colors.black;
  if (!parsed.isKelvin) {
    return HSVColor.fromAHSV(
      1,
      _wrapHue(parsed.hue!),
      _clamp(parsed.saturation!, 0, 100) / 100,
      _clamp(parsed.brightness, 0, 100) / 100,
    ).toColor();
  }
  final rgb = kelvinToRgb(parsed.kelvin!);
  final base = Color.fromARGB(255, rgb.red, rgb.green, rgb.blue);
  final hsv = HSVColor.fromColor(base);
  return HSVColor.fromAHSV(
    1,
    hsv.hue,
    hsv.saturation,
    _clamp(parsed.brightness, 0, 100) / 100,
  ).toColor();
}

RgbColor kelvinToRgb(double kelvin) {
  final temperature = kelvin / 100;
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;

  if (temperature <= 66) {
    red = 255;
    green = 99.4708025861 * math.log(temperature) - 161.1195681661;
  } else {
    red = 329.698727446 * math.pow(temperature - 60, -0.1332047592);
    green = 288.1221695283 * math.pow(temperature - 60, -0.0755148492);
  }

  if (temperature >= 66) {
    blue = 255;
  } else if (temperature <= 19) {
    blue = 0;
  } else {
    blue = 138.5177312231 * math.log(temperature - 10) - 305.0447927307;
  }

  return RgbColor(
    red: _clamp(red, 0, 255).round(),
    green: _clamp(green, 0, 255).round(),
    blue: _clamp(blue, 0, 255).round(),
  );
}

final class RgbColor {
  const RgbColor({required this.red, required this.green, required this.blue});

  final int red;
  final int green;
  final int blue;
}

double _clamp(double value, double min, double max) =>
    math.min(math.max(value, min), max);

double _wrapHue(double value) => (value % 360 + 360) % 360;

String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';