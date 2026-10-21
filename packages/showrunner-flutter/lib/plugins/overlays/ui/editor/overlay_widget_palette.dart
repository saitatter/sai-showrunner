import 'package:flutter/material.dart';

import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_widget_icons.dart';

class OverlayWidgetPalette extends StatefulWidget {
  const OverlayWidgetPalette({
    super.key,
    required this.catalog,
    required this.height,
    required this.onSelected,
  });

  final List<GeneratedOverlayWidget> catalog;
  final double height;
  final ValueChanged<GeneratedOverlayWidget> onSelected;

  @override
  State<OverlayWidgetPalette> createState() => _OverlayWidgetMenuState();
}

class _OverlayWidgetMenuState extends State<OverlayWidgetPalette> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.catalog
        .where(
          (definition) =>
              query.isEmpty ||
              definition.name.toLowerCase().contains(query) ||
              definition.id.toLowerCase().contains(query) ||
              definition.pluginId.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 300,
        height: widget.height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                key: const ValueKey('overlay-widget-search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search widgets',
                  isDense: true,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No widgets found'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final definition = filtered[index];
                        return InkWell(
                          onTap: () => widget.onSelected(definition),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                overlayWidgetIconWidget(definition),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    definition.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
