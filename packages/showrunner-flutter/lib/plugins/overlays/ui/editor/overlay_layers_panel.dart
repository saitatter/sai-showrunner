import 'package:flutter/material.dart';
import '../../../../schema/json.dart';
import '../../generated_widget_catalog.dart';
import '../../overlay_widget_icons.dart';
import 'overlay_editor_controller.dart';
import 'overlay_presence_controller.dart';
import 'overlay_layer_title.dart';
import 'overlay_widget_presentation.dart';

class OverlayLayersPanel extends StatelessWidget {
  const OverlayLayersPanel({
    super.key,
    required this.editor,
    required this.catalog,
    required this.presence,
    required this.header,
    this.footer,
    required this.onSelected,
    required this.onReorder,
    required this.onAction,
  });
  final OverlayEditorController editor;
  final List<GeneratedOverlayWidget> catalog;
  final ValueNotifier<OverlayPresenceView> presence;
  final Widget header;
  final Widget? footer;
  final ValueChanged<Object> onSelected;
  final void Function(int, int) onReorder;
  final void Function(Object, String) onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: editor.widgets.isEmpty
              ? const Center(child: Text('No widgets defined.'))
              : ReorderableListView.builder(
                  key: const ValueKey('overlay-widget-reorder-list'),
                  buildDefaultDragHandles: false,
                  itemCount: editor.widgets.length,
                  onReorderItem: onReorder,
                  itemBuilder: (context, index) {
                    final item = editor.widgets[index];
                    final layerKey = editor.keyAt(index);
                    final selected = index == editor.selectedIndex;
                    return Material(
                      key: ValueKey(
                        'overlay-widget-row-${item['id'] ?? index}',
                      ),
                      color: selected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .14)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => onSelected(layerKey),
                        child: SizedBox(
                          height: 58,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: LayoutBuilder(
                              builder: (context, constraints) => Row(
                                children: [
                                  Tooltip(
                                    message:
                                        'Drag to reorder (or use Widget actions)',
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.grab,
                                      child: ReorderableDragStartListener(
                                        index: index,
                                        child: const SizedBox(
                                          width: 36,
                                          height: 48,
                                          child: Center(
                                            child: Icon(
                                              Icons.drag_handle,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  KeyedSubtree(
                                    key: ValueKey(
                                      'overlay-widget-row-icon-${item['id']}',
                                    ),
                                    child: _widgetListIcon(item),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        OverlayLayerTitle(
                                          key: ValueKey(
                                            'overlay-layer-title-${item['id']}',
                                          ),
                                          widgetId: item['id'].toString(),
                                          name: OverlayWidgetPresentation.title(
                                            item,
                                            catalog,
                                          ),
                                          onSelected: () =>
                                              onSelected(layerKey),
                                          onRenamed: (name) {
                                            editor.updateWidget(layerKey, {
                                              'name': name,
                                            });
                                          },
                                        ),
                                        ValueListenableBuilder<
                                          OverlayPresenceView
                                        >(
                                          valueListenable: presence,
                                          builder: (context, view, _) => Text(
                                            _widgetListSubtitle(item, view),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey(
                                      'overlay-widget-visibility-${item['id']}',
                                    ),
                                    tooltip: item['visible'] == false
                                        ? 'Show widget'
                                        : 'Hide widget',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 30,
                                      height: 30,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () =>
                                        onAction(layerKey, 'visible'),
                                    icon: Icon(
                                      item['visible'] == false
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey(
                                      'overlay-widget-lock-${item['id']}',
                                    ),
                                    tooltip: item['locked'] == true
                                        ? 'Unlock widget'
                                        : 'Lock widget',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 30,
                                      height: 30,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () =>
                                        onAction(layerKey, 'locked'),
                                    icon: Icon(
                                      item['locked'] == true
                                          ? Icons.lock_outline
                                          : Icons.lock_open_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  if (constraints.maxWidth >= 280) ...[
                                    IconButton(
                                      key: ValueKey(
                                        'overlay-widget-list-move-up-${item['id']}',
                                      ),
                                      tooltip: 'Move up',
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 28,
                                            height: 28,
                                          ),
                                      padding: EdgeInsets.zero,
                                      onPressed: index == 0
                                          ? null
                                          : () => onAction(layerKey, 'up'),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_up,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'overlay-widget-list-move-down-${item['id']}',
                                      ),
                                      tooltip: 'Move down',
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 28,
                                            height: 28,
                                          ),
                                      padding: EdgeInsets.zero,
                                      onPressed:
                                          index == editor.widgets.length - 1
                                          ? null
                                          : () => onAction(layerKey, 'down'),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                  PopupMenuButton<String>(
                                    key: ValueKey(
                                      'overlay-widget-actions-${item['id']}',
                                    ),
                                    tooltip: 'Widget actions',
                                    padding: EdgeInsets.zero,
                                    iconSize: 18,
                                    onSelected: (action) {
                                      switch (action) {
                                        case 'rename':
                                          onAction(layerKey, 'rename');
                                          break;
                                        case 'up':
                                          onAction(layerKey, 'up');
                                          break;
                                        case 'down':
                                          onAction(layerKey, 'down');
                                          break;
                                        case 'delete':
                                          onAction(layerKey, 'delete');
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Text('Rename'),
                                      ),
                                      PopupMenuItem(
                                        value: 'up',
                                        enabled: index > 0,
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.keyboard_arrow_up,
                                              size: 18,
                                            ),
                                            SizedBox(width: 8),
                                            Text('Move up'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'down',
                                        enabled:
                                            index < editor.widgets.length - 1,
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.keyboard_arrow_down,
                                              size: 18,
                                            ),
                                            SizedBox(width: 8),
                                            Text('Move down'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (footer != null) ...[const Divider(height: 1), footer!],
      ],
    ),
  );
  String _widgetListSubtitle(JsonMap item, OverlayPresenceView view) {
    if (item['visible'] == false) return 'Hidden in overlay';
    if (view.presence.connected) {
      return 'Connected (${view.presence.subscribers})';
    }
    return 'OBS source disconnected';
  }

  Widget _widgetListIcon(JsonMap item) {
    final definition = catalog.cast<GeneratedOverlayWidget?>().firstWhere(
      (candidate) =>
          candidate?.pluginId == OverlayWidgetPresentation.pluginId(item) &&
          candidate?.id == OverlayWidgetPresentation.widgetId(item),
      orElse: () => null,
    );
    final icon = definition == null
        ? const Icon(Icons.widgets_outlined, size: 18)
        : overlayWidgetIconWidget(definition, size: 18);
    if (item['locked'] != true) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        const Positioned(
          right: -5,
          bottom: -5,
          child: Icon(Icons.lock, size: 10),
        ),
      ],
    );
  }
}
