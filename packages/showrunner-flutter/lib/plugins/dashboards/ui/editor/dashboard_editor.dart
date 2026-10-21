import 'dashboard_editor_values.dart';
import 'dashboard_resource_slot_dialog.dart';
import 'dashboard_widget_dialog.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/schema/json.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/plugins/dashboards/ui/dashboard_widget_config.dart';

import 'package:showrunner_flutter/components/data_inputs/resource_form.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_field_values.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_widget_presentation.dart';

class DashboardEditor extends StatefulWidget {
  const DashboardEditor({
    super.key,
    required this.resource,
    required this.onSave,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<DashboardEditor> createState() => _DashboardEditorState();
}

class _DashboardEditorState extends State<DashboardEditor> {
  late final TextEditingController _name;
  late final TextEditingController _remoteTwitchIds;
  late List<JsonMap> _pages;
  late List<JsonMap> _resourceSlots;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.resource.config['name']?.toString() ?? '',
    );
    _remoteTwitchIds = TextEditingController(
      text: ResourceFieldValues.strings(
        widget.resource.config['remoteTwitchIds'],
      ).join(', '),
    );
    _pages = ResourceFieldValues.maps(
      widget.resource.config['pages'],
    ).map(DashboardEditorValues.page).toList();
    _resourceSlots = ResourceFieldValues.maps(
      widget.resource.config['resourceSlots'],
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _remoteTwitchIds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResourceForm(
    title: 'Edit dashboard',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _remoteTwitchIds,
        decoration: const InputDecoration(
          labelText: 'Shared Twitch viewer IDs',
          hintText: 'Comma-separated IDs; leave empty for private',
        ),
      ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Pages',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add page',
            onPressed: _addPage,
            icon: const Icon(Icons.post_add_outlined),
          ),
        ],
      ),
      if (_pages.isEmpty)
        const Text('No pages defined.')
      else
        for (var index = 0; index < _pages.length; index++) _page(index),
      const SizedBox(height: 16),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Resource slots',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add resource slot',
            onPressed: _addResourceSlot,
            icon: const Icon(Icons.add_link),
          ),
        ],
      ),
      if (_resourceSlots.isEmpty)
        const Text('No remote resource slots defined.')
      else
        for (var index = 0; index < _resourceSlots.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: TextFormField(
              initialValue:
                  '${_resourceSlots[index]['name'] ?? 'Unnamed slot'}',
              decoration: const InputDecoration(labelText: 'Slot name'),
              onChanged: (value) => _resourceSlots[index]['name'] = value,
            ),
            subtitle: Text(
              '${_resourceSlots[index]['slotType'] ?? 'unknown'} · ${_resourceSlots[index]['id'] ?? ''}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Move slot up',
                  onPressed: index == 0
                      ? null
                      : () => setState(
                          () => ResourceFieldValues.moveListItem(
                            _resourceSlots,
                            index,
                            index - 1,
                          ),
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move slot down',
                  onPressed: index == _resourceSlots.length - 1
                      ? null
                      : () => setState(
                          () => ResourceFieldValues.moveListItem(
                            _resourceSlots,
                            index,
                            index + 1,
                          ),
                        ),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Delete resource slot',
                  onPressed: () =>
                      setState(() => _resourceSlots.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'pages': _pages,
          'remoteTwitchIds': _remoteTwitchIds.text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(),
          'resourceSlots': _resourceSlots,
        },
      ),
    ),
  );

  Widget _page(int pageIndex) {
    final page = _pages[pageIndex];
    final sections = (page['sections'] as List).cast<JsonMap>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '${page['name'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'Page name'),
                    onChanged: (value) => page['name'] = value,
                  ),
                ),
                IconButton(
                  tooltip: 'Move page up',
                  onPressed: pageIndex == 0
                      ? null
                      : () => setState(
                          () => ResourceFieldValues.moveListItem(
                            _pages,
                            pageIndex,
                            pageIndex - 1,
                          ),
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move page down',
                  onPressed: pageIndex == _pages.length - 1
                      ? null
                      : () => setState(
                          () => ResourceFieldValues.moveListItem(
                            _pages,
                            pageIndex,
                            pageIndex + 1,
                          ),
                        ),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Delete page',
                  onPressed: () => setState(() => _pages.removeAt(pageIndex)),
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: 'Add section',
                  onPressed: () => setState(
                    () => sections.add({
                      'id': DashboardEditorValues.newId('section'),
                      'name': 'New section',
                      'columns': 4,
                      'widgets': <JsonMap>[],
                    }),
                  ),
                  icon: const Icon(Icons.view_agenda_outlined),
                ),
              ],
            ),
            for (var index = 0; index < sections.length; index++)
              _section(sections, index),
          ],
        ),
      ),
    );
  }

  Widget _section(List<JsonMap> sections, int sectionIndex) {
    final section = sections[sectionIndex];
    final widgets = (section['widgets'] as List).cast<JsonMap>();
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '${section['name'] ?? ''}',
                  decoration: const InputDecoration(labelText: 'Section name'),
                  onChanged: (value) => section['name'] = value,
                ),
              ),
              DropdownButton<int>(
                value: (section['columns'] as num?)?.toInt() ?? 4,
                items: [
                  for (final columns in [1, 2, 3, 4, 6, 8, 12])
                    DropdownMenuItem(
                      value: columns,
                      child: Text('$columns columns'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => section['columns'] = value);
                },
              ),
              IconButton(
                tooltip: 'Move section up',
                onPressed: sectionIndex == 0
                    ? null
                    : () => setState(
                        () => ResourceFieldValues.moveListItem(
                          sections,
                          sectionIndex,
                          sectionIndex - 1,
                        ),
                      ),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move section down',
                onPressed: sectionIndex == sections.length - 1
                    ? null
                    : () => setState(
                        () => ResourceFieldValues.moveListItem(
                          sections,
                          sectionIndex,
                          sectionIndex + 1,
                        ),
                      ),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Delete section',
                onPressed: () =>
                    setState(() => sections.removeAt(sectionIndex)),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: 'Add widget',
                onPressed: () => _addWidget(widgets),
                icon: const Icon(Icons.widgets_outlined),
              ),
            ],
          ),
          for (var index = 0; index < widgets.length; index++)
            ListTile(
              dense: true,
              onTap: () => _editWidget(widgets, index),
              leading: const Icon(Icons.widgets_outlined),
              title: Text(OverlayWidgetPresentation.title(widgets[index])),
              subtitle: Text(
                '${widgets[index]['plugin'] ?? 'unknown'} / ${widgets[index]['widget'] ?? widgets[index]['type'] ?? 'unknown'}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Move widget up',
                    onPressed: index == 0
                        ? null
                        : () => setState(
                            () => ResourceFieldValues.moveListItem(
                              widgets,
                              index,
                              index - 1,
                            ),
                          ),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move widget down',
                    onPressed: index == widgets.length - 1
                        ? null
                        : () => setState(
                            () => ResourceFieldValues.moveListItem(
                              widgets,
                              index,
                              index + 1,
                            ),
                          ),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: 'Delete widget',
                    onPressed: () => setState(() => widgets.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _addPage() => setState(
    () => _pages.add({
      'id': DashboardEditorValues.newId('page'),
      'name': 'New page',
      'sections': <JsonMap>[],
    }),
  );

  Future<void> _editWidget(List<JsonMap> widgets, int index) async {
    final updated = await showDialog<JsonMap>(
      context: context,
      builder: (context) => DashboardWidgetDialog(widget: widgets[index]),
    );
    if (updated != null && mounted) setState(() => widgets[index] = updated);
  }

  Future<void> _addResourceSlot() async {
    final slot = await showDialog<JsonMap>(
      context: context,
      builder: (context) => const DashboardResourceSlotDialog(),
    );
    if (slot != null && mounted) setState(() => _resourceSlots.add(slot));
  }

  Future<void> _addWidget(List<JsonMap> widgets) async {
    final definition = await showDialog<DashboardWidgetDefinition>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add dashboard widget'),
        children: [
          for (final option in dashboardWidgetDefinitions)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.widgets_outlined),
                title: Text(option.name),
                subtitle: Text('${option.plugin}.${option.widget}'),
              ),
            ),
        ],
      ),
    );
    if (definition == null || !mounted) return;
    setState(
      () => widgets.add(
        definition.createWidget(id: DashboardEditorValues.newId('widget')),
      ),
    );
  }
}
