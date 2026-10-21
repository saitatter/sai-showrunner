import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OverlayLayerTitle extends StatefulWidget {
  const OverlayLayerTitle({
    super.key,
    required this.widgetId,
    required this.name,
    required this.onSelected,
    required this.onRenamed,
  });
  final String widgetId;
  final String name;
  final VoidCallback onSelected;
  final ValueChanged<String> onRenamed;
  @override
  State<OverlayLayerTitle> createState() => _OverlayLayerTitleState();
}

class _OverlayLayerTitleState extends State<OverlayLayerTitle> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _finish();
    });
  }

  void _start() {
    widget.onSelected();
    _controller.value = TextEditingValue(
      text: widget.name,
      selection: TextSelection(baseOffset: 0, extentOffset: widget.name.length),
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _finish({bool cancel = false}) {
    if (!_editing) return;
    final name = _controller.text.trim();
    setState(() => _editing = false);
    if (!cancel && name.isNotEmpty && name != widget.name) {
      widget.onRenamed(name);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _editing
      ? Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _finish(cancel: true);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: ValueKey('overlay-layer-rename-${widget.widgetId}'),
            controller: _controller,
            focusNode: _focus,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
            onSubmitted: (_) => _finish(),
            onTapOutside: (_) => _finish(),
          ),
        )
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelected,
          onDoubleTap: _start,
          child: Text(
            widget.name,
            key: ValueKey('overlay-widget-row-title-${widget.widgetId}'),
            semanticsLabel: widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        );
}
