import 'package:flutter/material.dart';
import '../../schema/data_input.dart';
import 'style/text_style_input.dart';
import 'style/alignment_inputs.dart';
import 'style/geometry_inputs.dart';
import 'style/outline_input.dart';
import 'style/background_input.dart';
export 'style/alignment_inputs.dart' show OverlayLabelAlignmentInput;

/// Routes structured overlay schemas to their focused editor controls.
class OverlayStyleInput extends StatelessWidget {
  const OverlayStyleInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) => switch (schema.editor) {
    'overlayTextStyle' => OverlayTextStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'overlayTextAlignment' => OverlayTextAlignmentInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'overlayBlockStyle' => OverlayBlockStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'widgetBorderRadius' => WidgetBorderRadiusInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'widgetBackgroundStyle' => WidgetBackgroundStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'widgetOutlineStyle' => WidgetOutlineStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    _ => const SizedBox.shrink(),
  };
}
