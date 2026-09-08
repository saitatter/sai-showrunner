import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/showrunner_graph_editor.dart';

/// Find overlay for the graph canvas.
///
/// The node picker has its own search field because it inserts new nodes. This
/// control is deliberately separate: it searches the existing graph and is
/// opened on demand with Ctrl/Cmd+F, just like the desktop editor.
class GraphCanvasSearch extends StatefulWidget {
  const GraphCanvasSearch({super.key, required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  State<GraphCanvasSearch> createState() => _GraphCanvasSearchState();
}

class _GraphCanvasSearchState extends State<GraphCanvasSearch> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  ShowRunnerGraphEditor get editor => widget.editor;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: editor.searchQuery.value);
    _focusNode = FocusNode(debugLabel: 'graph-canvas-search');
    editor.canvasSearchOpen.addListener(_handleOpenChanged);
    _handleOpenChanged();
  }

  @override
  void dispose() {
    editor.canvasSearchOpen.removeListener(_handleOpenChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleOpenChanged() {
    if (!editor.canvasSearchOpen.value) return;
    _textController.value = TextEditingValue(
      text: editor.searchQuery.value,
      selection: TextSelection.collapsed(
        offset: editor.searchQuery.value.length,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editor.canvasSearchOpen.value) _focusNode.requestFocus();
    });
  }

  void _cycle({required bool forward}) {
    editor.focusSearchResult(forward: forward);
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      editor.closeCanvasSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _cycle(forward: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _cycle(forward: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      _cycle(forward: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.canvasSearchOpen,
      editor.searchQuery,
      editor.searchMatchIndex,
      editor.nodeRevision,
    ]),
    builder: (context, child) {
      if (!editor.canvasSearchOpen.value) return const SizedBox.shrink();

      final resultCount = editor.searchResultCount();
      final current = resultCount == 0
          ? 0
          : (editor.searchMatchIndex.value % resultCount) + 1;
      return Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xf0151515),
              border: Border.all(color: const Color(0xff454545)),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.search, size: 17, color: Color(0xffd6a1ff)),
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    autofocus: false,
                    onChanged: editor.setSearchQuery,
                    onSubmitted: (_) => _cycle(forward: true),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    cursorColor: const Color(0xffe9aaff),
                    decoration: const InputDecoration(
                      hintText: 'Find node…',
                      hintStyle: TextStyle(color: Color(0xff9e9e9e)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                Text(
                  resultCount == 0 ? '0' : '$current/$resultCount',
                  style: const TextStyle(
                    color: Color(0xffbdbdbd),
                    fontSize: 11,
                  ),
                ),
                IconButton(
                  tooltip: 'Previous match',
                  onPressed: resultCount == 0
                      ? null
                      : () => _cycle(forward: false),
                  icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  color: const Color(0xffe9aaff),
                  disabledColor: const Color(0xff706477),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
                IconButton(
                  tooltip: 'Next match',
                  onPressed: resultCount == 0
                      ? null
                      : () => _cycle(forward: true),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  color: const Color(0xffe9aaff),
                  disabledColor: const Color(0xff706477),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
                IconButton(
                  tooltip: 'Close graph search',
                  onPressed: editor.closeCanvasSearch,
                  icon: const Icon(Icons.close, size: 17),
                  color: const Color(0xffe9aaff),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
