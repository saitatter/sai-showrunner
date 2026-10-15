part of '../resource_editor_registry.dart';

class _DashboardEditor extends StatefulWidget {
  const _DashboardEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_DashboardEditor> createState() => _DashboardEditorState();
}

class _DashboardEditorState extends State<_DashboardEditor> {
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
      text: _strings(widget.resource.config['remoteTwitchIds']).join(', '),
    );
    _pages = _maps(
      widget.resource.config['pages'],
    ).map(_dashboardPage).toList();
    _resourceSlots = _maps(widget.resource.config['resourceSlots']);
  }

  @override
  void dispose() {
    _name.dispose();
    _remoteTwitchIds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
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
                          () => _moveListItem(_resourceSlots, index, index - 1),
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move slot down',
                  onPressed: index == _resourceSlots.length - 1
                      ? null
                      : () => setState(
                          () => _moveListItem(_resourceSlots, index, index + 1),
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
                          () => _moveListItem(_pages, pageIndex, pageIndex - 1),
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move page down',
                  onPressed: pageIndex == _pages.length - 1
                      ? null
                      : () => setState(
                          () => _moveListItem(_pages, pageIndex, pageIndex + 1),
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
                      'id': _newDashboardId('section'),
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
                        () => _moveListItem(
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
                        () => _moveListItem(
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
              title: Text(_widgetTitle(widgets[index])),
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
                            () => _moveListItem(widgets, index, index - 1),
                          ),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move widget down',
                    onPressed: index == widgets.length - 1
                        ? null
                        : () => setState(
                            () => _moveListItem(widgets, index, index + 1),
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
      'id': _newDashboardId('page'),
      'name': 'New page',
      'sections': <JsonMap>[],
    }),
  );

  Future<void> _editWidget(List<JsonMap> widgets, int index) async {
    final updated = await showDialog<JsonMap>(
      context: context,
      builder: (context) => _DashboardWidgetDialog(widget: widgets[index]),
    );
    if (updated != null && mounted) setState(() => widgets[index] = updated);
  }

  Future<void> _addResourceSlot() async {
    final slot = await showDialog<JsonMap>(
      context: context,
      builder: (context) => const _DashboardResourceSlotDialog(),
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
      () => widgets.add(definition.createWidget(id: _newDashboardId('widget'))),
    );
  }
}

class _DashboardWidgetDialog extends StatefulWidget {
  const _DashboardWidgetDialog({required this.widget});

  final JsonMap widget;

  @override
  State<_DashboardWidgetDialog> createState() => _DashboardWidgetDialogState();
}

class _DashboardWidgetDialogState extends State<_DashboardWidgetDialog> {
  late final TextEditingController _plugin;
  late final TextEditingController _widget;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _config;
  late JsonMap _configValue;
  String? _error;

  @override
  void initState() {
    super.initState();
    final size = widget.widget['size'] is Map
        ? Map<String, dynamic>.from(widget.widget['size'] as Map)
        : const <String, dynamic>{};
    _plugin = TextEditingController(
      text: widget.widget['plugin']?.toString() ?? 'dashboards',
    );
    _widget = TextEditingController(
      text: widget.widget['widget']?.toString() ?? 'label',
    );
    _width = TextEditingController(text: '${size['width'] ?? 4}');
    _height = TextEditingController(text: '${size['height'] ?? 1}');
    _configValue = widget.widget['config'] is Map
        ? Map<String, dynamic>.from(widget.widget['config'] as Map)
        : <String, dynamic>{};
    _config = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(_configValue),
    );
  }

  @override
  void dispose() {
    for (final controller in [_plugin, _widget, _width, _height, _config]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit dashboard widget'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _plugin,
              decoration: const InputDecoration(labelText: 'Plugin'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _widget,
              decoration: const InputDecoration(labelText: 'Widget'),
              onChanged: (_) => setState(() {}),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _width,
                    inputFormatters: const [
                      NumericInputFormatter(decimal: false, signed: false),
                    ],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Width'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _height,
                    inputFormatters: const [
                      NumericInputFormatter(decimal: false, signed: false),
                    ],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Height'),
                  ),
                ),
              ],
            ),
            _configEditor(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  void _save() {
    final definition = findDashboardWidgetDefinition(
      _plugin.text.trim(),
      _widget.text.trim(),
    );
    JsonMap config;
    if (definition != null) {
      config = _configValue;
    } else {
      dynamic decoded;
      try {
        decoded = jsonDecode(_config.text);
      } on FormatException {
        setState(() => _error = 'Widget config must be valid JSON.');
        return;
      }
      if (decoded is! Map) {
        setState(() => _error = 'Widget config must be a JSON object.');
        return;
      }
      config = Map<String, dynamic>.from(decoded);
    }
    Navigator.pop(context, {
      ...widget.widget,
      'plugin': _plugin.text.trim(),
      'widget': _widget.text.trim(),
      'size': {
        'width': int.tryParse(_width.text) ?? 4,
        'height': int.tryParse(_height.text) ?? 1,
      },
      'config': config,
    });
  }

  Widget _configEditor() {
    final definition = findDashboardWidgetDefinition(
      _plugin.text.trim(),
      _widget.text.trim(),
    );
    if (definition == null) {
      return TextField(
        controller: _config,
        maxLines: 8,
        decoration: const InputDecoration(labelText: 'Widget config JSON'),
      );
    }
    return DartDataInput(
      key: ValueKey('${definition.plugin}.${definition.widget}'),
      schema: definition.configSchema,
      value: _configValue,
      onChanged: (value) {
        if (value is Map) {
          setState(() => _configValue = Map<String, dynamic>.from(value));
        }
      },
    );
  }
}

class _DashboardResourceSlotDialog extends StatefulWidget {
  const _DashboardResourceSlotDialog();

  @override
  State<_DashboardResourceSlotDialog> createState() =>
      _DashboardResourceSlotDialogState();
}

class _DashboardResourceSlotDialogState
    extends State<_DashboardResourceSlotDialog> {
  final _name = TextEditingController();
  final _type = TextEditingController(text: 'SoundOutput');

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add resource slot'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _type,
          decoration: const InputDecoration(labelText: 'Slot type'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          final type = _type.text.trim();
          if (name.isEmpty || type.isEmpty) return;
          Navigator.pop(context, {
            'id': _newDashboardId('slot'),
            'name': name,
            'slotType': type,
            'config': <String, dynamic>{},
          });
        },
        child: const Text('Add'),
      ),
    ],
  );
}
