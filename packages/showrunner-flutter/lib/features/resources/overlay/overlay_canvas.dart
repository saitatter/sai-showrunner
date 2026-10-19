part of '../resource_editor_registry.dart';

class _OverlayAlignmentPainter extends CustomPainter {
  const _OverlayAlignmentPainter(this.vertical, this.horizontal, this.scale);
  final List<double> vertical;
  final List<double> horizontal;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff4cc9ff)
      ..strokeWidth = 1;
    for (final x in vertical) {
      for (var y = 0.0; y < size.height; y += 9) {
        canvas.drawLine(
          Offset(x * scale, y),
          Offset(x * scale, math.min(y + 5, size.height)),
          paint,
        );
      }
    }
    for (final y in horizontal) {
      for (var x = 0.0; x < size.width; x += 9) {
        canvas.drawLine(
          Offset(x, y * scale),
          Offset(math.min(x + 5, size.width), y * scale),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayAlignmentPainter old) =>
      old.vertical != vertical ||
      old.horizontal != horizontal ||
      old.scale != scale;
}

enum _OverlayResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get movesLeft => switch (this) {
    topLeft || bottomLeft || left => true,
    _ => false,
  };

  bool get movesRight => switch (this) {
    topRight || bottomRight || right => true,
    _ => false,
  };

  bool get movesTop => switch (this) {
    topLeft || topRight || top => true,
    _ => false,
  };

  bool get movesBottom => switch (this) {
    bottomLeft || bottomRight || bottom => true,
    _ => false,
  };

  MouseCursor get cursor => switch (this) {
    topLeft || bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    topRight || bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    top || bottom => SystemMouseCursors.resizeUpDown,
    left || right => SystemMouseCursors.resizeLeftRight,
  };
}

class _OverlayCanvas extends StatelessWidget {
  const _OverlayCanvas({
    required this.width,
    required this.height,
    required this.widgets,
    required this.selectedIndex,
    required this.catalog,
    required this.onSelect,
    required this.onMove,
    required this.onResize,
    required this.onTransformStart,
    required this.onTransformEnd,
    required this.verticalGuides,
    required this.horizontalGuides,
    required this.onDeselect,
  });

  final int width;
  final int height;
  final List<JsonMap> widgets;
  final int? selectedIndex;
  final List<GeneratedOverlayWidget> catalog;
  final ValueChanged<int> onSelect;
  final VoidCallback onDeselect;
  final ValueChanged<int> onTransformStart;
  final VoidCallback onTransformEnd;
  final List<double> verticalGuides;
  final List<double> horizontalGuides;
  final void Function(int index, Offset delta, double tolerance) onMove;
  final void Function(
    int index,
    _OverlayResizeHandle handle,
    Offset delta,
    double tolerance,
  )
  onResize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = math.max(80.0, constraints.maxWidth);
      final availableHeight = math.max(80.0, constraints.maxHeight);
      final scale = math.min(
        availableWidth / math.max(1, width),
        availableHeight / math.max(1, height),
      );
      final stageWidth = width * scale;
      final stageHeight = height * scale;
      return ColoredBox(
        color: const Color(0xff202020),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDeselect,
          child: Stack(
            key: const ValueKey('overlay-canvas-viewport'),
            children: [
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey('overlay-canvas-grid'),
                  painter: _OverlayGridPainter(
                    horizontalStep: width * scale / 10,
                    verticalStep: height * scale / 10,
                    gridColor: const Color(0xff383838),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  key: const ValueKey('overlay-preview-stage'),
                  width: stageWidth,
                  height: stageHeight,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellow, width: 1),
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (var index = 0; index < widgets.length; index++)
                        _buildCanvasWidget(
                          context,
                          widgets[index],
                          index,
                          scale,
                        ),
                      if (verticalGuides.isNotEmpty ||
                          horizontalGuides.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              key: const ValueKey('overlay-alignment-guides'),
                              painter: _OverlayAlignmentPainter(
                                verticalGuides,
                                horizontalGuides,
                                scale,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Text('$width × $height'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildCanvasWidget(
    BuildContext context,
    JsonMap widgetConfig,
    int index,
    double scale,
  ) {
    final position = widgetConfig['position'] is Map
        ? Map<String, dynamic>.from(widgetConfig['position'] as Map)
        : const <String, dynamic>{};
    final size = widgetConfig['size'] is Map
        ? Map<String, dynamic>.from(widgetConfig['size'] as Map)
        : const <String, dynamic>{};
    final x = (position['x'] as num?)?.toDouble() ?? 0;
    final y = (position['y'] as num?)?.toDouble() ?? 0;
    final widgetWidth = (size['width'] as num?)?.toDouble() ?? 320;
    final widgetHeight = (size['height'] as num?)?.toDouble() ?? 80;
    final selected = index == selectedIndex;
    final hidden = widgetConfig['visible'] == false;
    final locked = widgetConfig['locked'] == true;
    final kind = widgetConfig['widget']?.toString() ?? 'widget';
    final pluginId = _definitionPluginId(widgetConfig);
    final widgetId = _definitionWidgetId(widgetConfig);
    final isLabel = widgetId == 'label';
    final definition = catalog.cast<GeneratedOverlayWidget?>().firstWhere(
      (candidate) =>
          candidate?.pluginId == pluginId && candidate?.id == widgetId,
      orElse: () => null,
    );
    final label = _widgetTitle(widgetConfig, catalog);
    final rawConfig = widgetConfig['config'];
    final config = isLabel && definition != null
        ? mergeOverlayWidgetDefaults(definition.configSchema, rawConfig)
        : rawConfig;
    final message = config is Map ? config['message']?.toString() : null;
    final displayTitle = isLabel && message?.trim().isNotEmpty == true
        ? message!
        : definition?.name ?? label;

    return Positioned(
      left: x * scale,
      top: y * scale,
      width: math.max(12, widgetWidth * scale),
      height: math.max(12, widgetHeight * scale),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(index),
            onPanStart: (_) {
              onTransformStart(index);
              onSelect(index);
            },
            onPanEnd: (_) => onTransformEnd(),
            onPanCancel: onTransformEnd,
            onPanUpdate: locked || hidden
                ? null
                : (details) => onMove(index, details.delta / scale, 6 / scale),
            child: AnimatedContainer(
              key: ValueKey('overlay-canvas-widget-box-${widgetConfig['id']}'),
              duration: const Duration(milliseconds: 90),
              padding: isLabel
                  ? EdgeInsets.zero
                  : EdgeInsets.all(math.max(3, 6 * scale)),
              decoration: BoxDecoration(
                color: isLabel
                    ? Colors.transparent
                    : _overlayWidgetColor(kind, hidden),
                border: selected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : isLabel
                    ? null
                    : Border.all(
                        color: Theme.of(context).colorScheme.outline,
                        width: 1,
                      ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Opacity(
                opacity: hidden ? .35 : 1,
                child: isLabel
                    ? _buildLabelPreview(
                        config: config,
                        message: message ?? 'Label',
                        scale: scale,
                        index: index,
                      )
                    : FittedBox(
                        alignment: Alignment.topLeft,
                        fit: BoxFit.scaleDown,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: math.max(12, widgetWidth * scale - 12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                locked
                                    ? Icons.lock_outline
                                    : Icons.widgets_outlined,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Column(
                                key: ValueKey('overlay-canvas-widget-$index'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (message?.trim().isNotEmpty == true)
                                    Text(
                                      message!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          if (selected && !locked && !hidden)
            for (final handle in _OverlayResizeHandle.values)
              _buildResizeHandle(context, index, handle, scale),
        ],
      ),
    );
  }

  Widget _buildLabelPreview({
    required Object? config,
    required String message,
    required double scale,
    required int index,
  }) {
    final values = config is Map
        ? Map<String, dynamic>.from(config)
        : const <String, dynamic>{};
    final font = values['font'] is Map
        ? Map<String, dynamic>.from(values['font'] as Map)
        : const <String, dynamic>{};
    final textAlign = values['textAlign'] is Map
        ? Map<String, dynamic>.from(values['textAlign'] as Map)
        : const <String, dynamic>{};
    final block = values['block'] is Map
        ? Map<String, dynamic>.from(values['block'] as Map)
        : const <String, dynamic>{};
    final textStyle = TextStyle(
      color: _overlayColor(font['fontColor'], Colors.white),
      fontFamily: font['fontFamily']?.toString().trim().isEmpty == true
          ? null
          : font['fontFamily']?.toString(),
      fontSize: math.max(
        .1,
        ((font['fontSize'] as num?)?.toDouble() ?? 65) * scale,
      ),
      fontWeight: _overlayFontWeight(font['fontWeight']),
      shadows: font['shadow'] is Map
          ? [
              Shadow(
                color: _overlayColor(
                  (font['shadow'] as Map)['color'],
                  Colors.transparent,
                ),
                offset: Offset(
                  (((font['shadow'] as Map)['offsetX'] as num?)?.toDouble() ??
                          0) *
                      scale,
                  (((font['shadow'] as Map)['offsetY'] as num?)?.toDouble() ??
                          0) *
                      scale,
                ),
                blurRadius:
                    (((font['shadow'] as Map)['blur'] as num?)?.toDouble() ??
                        0) *
                    scale,
              ),
            ]
          : const [],
    );
    final stroke = font['stroke'] is Map
        ? Map<String, dynamic>.from(font['stroke'] as Map)
        : const <String, dynamic>{};
    final strokeWidth = ((stroke['width'] as num?)?.toDouble() ?? 0) * scale;
    final alignment = _overlayTextAlign(textAlign['textAlign']);
    final fillTextStyle = strokeWidth > 0
        ? textStyle.copyWith(shadows: const [])
        : textStyle;
    Widget labelText(TextStyle style, {Key? key}) => Text(
      message,
      key: key,
      maxLines: null,
      softWrap: true,
      textWidthBasis: TextWidthBasis.parent,
      textScaler: TextScaler.noScaling,
      textAlign: alignment,
      style: style,
    );
    final text = labelText(
      fillTextStyle,
      key: ValueKey('overlay-canvas-widget-$index'),
    );
    final content = strokeWidth > 0
        ? Stack(
            fit: StackFit.passthrough,
            children: [
              labelText(
                textStyle.copyWith(
                  color: null,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = strokeWidth
                    ..color = _overlayColor(stroke['color'], Colors.black),
                ),
              ),
              text,
            ],
          )
        : text;
    final verticalAlignment = switch (block['verticalAlign']?.toString()) {
      'center' => 0.0,
      'bottom' => 1.0,
      _ => -1.0,
    };
    final padding = block['padding'] is Map
        ? Map<String, dynamic>.from(block['padding'] as Map)
        : const <String, dynamic>{};
    // Vue's full-size flex container positions its width:100% text child
    // vertically. Keep the text at its natural height (it may exceed a small
    // widget, just as the browser renderer permits) while constraining its
    // width so horizontal text alignment is visible.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ((padding['left'] as num?)?.toDouble() ?? 0) * scale,
        ((padding['top'] as num?)?.toDouble() ?? 0) * scale,
        ((padding['right'] as num?)?.toDouble() ?? 0) * scale,
        ((padding['bottom'] as num?)?.toDouble() ?? 0) * scale,
      ),
      child: SizedBox.expand(
        child: Stack(
          key: ValueKey('overlay-canvas-label-layout-$index'),
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment(0, verticalAlignment),
              child: FractionallySizedBox(
                widthFactor: 1,
                alignment: Alignment.centerLeft,
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _overlayColor(Object? value, Color fallback) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    if (hex.length == 6) return Color(0xff000000 | parsed);
    if (hex.length == 8) return Color(((parsed & 255) << 24) | (parsed >> 8));
    return fallback;
  }

  FontWeight _overlayFontWeight(Object? value) {
    final number = (value is num ? value : num.tryParse('$value'))?.round();
    final index = (((number ?? 400).clamp(100, 900) - 100) / 100).round();
    return FontWeight.values[index];
  }

  TextAlign _overlayTextAlign(Object? value) => switch (value?.toString()) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    'justify' => TextAlign.justify,
    _ => TextAlign.left,
  };

  Widget _buildResizeHandle(
    BuildContext context,
    int index,
    _OverlayResizeHandle handle,
    double scale,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    final alignment = switch (handle) {
      _OverlayResizeHandle.topLeft => Alignment.topLeft,
      _OverlayResizeHandle.top => Alignment.topCenter,
      _OverlayResizeHandle.topRight => Alignment.topRight,
      _OverlayResizeHandle.right => Alignment.centerRight,
      _OverlayResizeHandle.bottomRight => Alignment.bottomRight,
      _OverlayResizeHandle.bottom => Alignment.bottomCenter,
      _OverlayResizeHandle.bottomLeft => Alignment.bottomLeft,
      _OverlayResizeHandle.left => Alignment.centerLeft,
    };
    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: handle.cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(index),
          onPanStart: (_) {
            onTransformStart(index);
            onSelect(index);
          },
          onPanEnd: (_) => onTransformEnd(),
          onPanCancel: onTransformEnd,
          onPanUpdate: (details) =>
              onResize(index, handle, details.delta / scale, 6 / scale),
          child: DecoratedBox(
            key: ValueKey('overlay-resize-$index-${handle.name}'),
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.white, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );
  }

  Color _overlayWidgetColor(String kind, bool hidden) {
    if (hidden) return Colors.grey.withValues(alpha: .12);
    if (kind.contains('shader')) return const Color(0xff3f2d61);
    if (kind.contains('chat')) return const Color(0xff243d52);
    if (kind.contains('alert') || kind.contains('paid')) {
      return const Color(0xff523228);
    }
    if (kind.contains('scene') || kind.contains('banner')) {
      return const Color(0xff27493e);
    }
    return const Color(0xff28303a);
  }
}

class _OverlayGridPainter extends CustomPainter {
  const _OverlayGridPainter({
    required this.horizontalStep,
    required this.verticalStep,
    required this.gridColor,
  });

  final double horizontalStep;
  final double verticalStep;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += horizontalStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += verticalStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayGridPainter oldDelegate) =>
      oldDelegate.horizontalStep != horizontalStep ||
      oldDelegate.verticalStep != verticalStep ||
      oldDelegate.gridColor != gridColor;
}
