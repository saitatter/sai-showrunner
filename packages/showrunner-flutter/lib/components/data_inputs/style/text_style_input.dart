import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import 'font_style_editor.dart';
import 'style_values.dart';

class OverlayTextStyleInput extends StatefulWidget {
  const OverlayTextStyleInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<OverlayTextStyleInput> createState() => _OverlayTextStyleInputState();
}

class _OverlayTextStyleInputState extends State<OverlayTextStyleInput> {
  final _portal = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final values = styleMap(widget.value);
    final family = styleField(widget.schema, 'fontFamily');
    final familyName = values['fontFamily']?.toString() ?? '';
    final fontColor = _color(values['fontColor'], Colors.white);
    final fontSize = (values['fontSize'] as num?)?.toDouble() ?? 16;
    final fontWeight = _fontWeight(values['fontWeight']);
    final stroke = styleMap(values['stroke']);
    final shadow = styleMap(values['shadow']);
    final previewScale = 16 / math.max(.1, fontSize);
    final previewStyle = TextStyle(
      color: fontColor,
      fontFamily: familyName.isEmpty ? null : familyName,
      fontSize: 16,
      fontWeight: fontWeight,
      shadows: values['shadow'] is Map
          ? [
              Shadow(
                color: _color(shadow['color'], Colors.transparent),
                offset: Offset(
                  ((shadow['offsetX'] as num?)?.toDouble() ?? 0) * previewScale,
                  ((shadow['offsetY'] as num?)?.toDouble() ?? 0) * previewScale,
                ),
                blurRadius:
                    ((shadow['blur'] as num?)?.toDouble() ?? 0) * previewScale,
              ),
            ]
          : const [],
    );
    final preview = Stack(
      children: [
        if (values['stroke'] is Map &&
            ((stroke['width'] as num?)?.toDouble() ?? 0) > 0)
          Text(
            familyName.isEmpty ? 'Choose a font' : familyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: previewStyle.copyWith(
              color: null,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth =
                    ((stroke['width'] as num?)?.toDouble() ?? 0) * previewScale
                ..color = _color(stroke['color'], Colors.black),
            ),
          ),
        Text(
          familyName.isEmpty ? 'Choose a font' : familyName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: previewStyle,
        ),
      ],
    );

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (overlayContext, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final width = math.min(
          640.0,
          math.max(1.0, info.overlaySize.width - 24),
        );
        final height = math.min(
          460.0,
          math.max(1.0, info.overlaySize.height - 24),
        );
        final left = (anchor.right - width).clamp(
          12.0,
          math.max(12.0, info.overlaySize.width - width - 12),
        );
        final top = (anchor.bottom + 4).clamp(
          12.0,
          math.max(12.0, info.overlaySize.height - height - 12),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _portal.hide,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              child: RepaintBoundary(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height),
                  child: OverlayFontStyleEditor(
                    key: ValueKey(
                      'overlay-font-editor-${widget.schema.key ?? widget.schema.label}',
                    ),
                    width: width,
                    schema: widget.schema,
                    value: values,
                    onChanged: widget.onChanged,
                    onClose: _portal.hide,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: InkWell(
        key: ValueKey(
          'overlay-font-style-${widget.schema.key ?? widget.schema.label}',
        ),
        borderRadius: BorderRadius.circular(4),
        onTap: family == null
            ? null
            : () {
                if (_portal.isShowing) {
                  _portal.hide();
                } else {
                  _portal.show();
                }
              },
        child: InputDecorator(
          isEmpty: familyName.isEmpty,
          decoration: InputDecoration(
            labelText: widget.schema.label,
            suffixIcon: const Icon(Icons.arrow_drop_down),
            isDense: true,
          ),
          child: ClipRect(child: RepaintBoundary(child: preview)),
        ),
      ),
    );
  }

  Color _color(Object? value, Color fallback) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return switch (hex.length) {
      6 => Color(0xff000000 | parsed),
      8 => Color(((parsed & 255) << 24) | (parsed >> 8)),
      _ => fallback,
    };
  }

  FontWeight _fontWeight(Object? value) {
    final number = (value is num ? value : num.tryParse('$value'))?.round();
    return FontWeight.values[((((number ?? 400).clamp(100, 900) - 100) / 100)
            .round())
        .clamp(0, 8)];
  }
}
