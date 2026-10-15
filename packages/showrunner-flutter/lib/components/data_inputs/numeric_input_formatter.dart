import 'package:flutter/services.dart';

/// Rejects invalid edits rather than silently changing pasted text into a
/// different number. Empty and partial numbers remain editable.
class NumericInputFormatter extends TextInputFormatter {
  const NumericInputFormatter({this.decimal = true, this.signed = true});

  final bool decimal;
  final bool signed;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = decimal ? newValue.text.replaceAll(',', '.') : newValue.text;
    final pattern =
        '${signed ? '-?' : ''}[0-9]*${decimal ? r'(\.[0-9]*)?' : ''}';
    if (RegExp('^$pattern\$').matchAsPrefix(text)?.end != text.length) {
      return oldValue;
    }
    return newValue.copyWith(text: text);
  }
}
