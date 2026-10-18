part of '../resource_editor_registry.dart';

class StreamPlanEditorPage extends StatefulWidget {
  const StreamPlanEditorPage({
    super.key,
    required this.resource,
    required this.onSave,
    this.registryFuture,
    this.resourceOptionsLoader,
    this.documentMode = false,
    this.onDocumentChanged,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;
  final Future<DartPluginRegistry>? registryFuture;
  final ResourceOptionsLoader? resourceOptionsLoader;
  final bool documentMode;
  final void Function(ResourceData resource, bool dirty)? onDocumentChanged;

  @override
  State<StreamPlanEditorPage> createState() => _StreamPlanEditorPageState();
}

class _StreamPlanEditorPageState extends State<StreamPlanEditorPage> {
  late final TextEditingController _name;
  late List<StreamPlanSegmentData> _segments;
  late final StreamPlanData _initialPlan;
  late String _savedBaseline;
  final Map<String, GlobalKey<_StreamPlanSegmentCardState>> _segmentKeys = {};
  AutomationEditorController? _activationEditor;
  AutomationEditorController? _deactivationEditor;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.resource.name);
    _segments = [];
    try {
      final plan = _initialPlan = StreamPlanData.fromConfig(
        widget.resource.config,
      );
      _name.text = plan.name;
      _segments = List<StreamPlanSegmentData>.of(plan.segments);
      if (widget.registryFuture != null) {
        _activationEditor = AutomationEditorController(
          document: AutomationDocument.fromJson(plan.activationAutomation),
        );
        _deactivationEditor = AutomationEditorController(
          document: AutomationDocument.fromJson(plan.deactivationAutomation),
        );
        _activationEditor!.graph.addDocumentListener(_graphChanged);
        _deactivationEditor!.graph.addDocumentListener(_graphChanged);
      }
      _savedBaseline = jsonEncode(_savedConfig());
    } catch (error) {
      _loadError = error;
    }
  }

  void _graphChanged(GraphDocumentChange change) => _notifyDirty();

  @override
  void dispose() {
    _name.dispose();
    _activationEditor?.graph.removeDocumentListener(_graphChanged);
    _deactivationEditor?.graph.removeDocumentListener(_graphChanged);
    _activationEditor?.dispose();
    _deactivationEditor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stream plan could not be opened'),
            const SizedBox(height: 12),
            SelectableText('$_loadError'),
          ],
        ),
      );
    }
    final fields = <Widget>[
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => _notifyDirty(),
      ),
      if (_activationEditor != null)
        _inlineStreamPlanAutomation('On Activate', _activationEditor!),
      if (_deactivationEditor != null)
        _inlineStreamPlanAutomation('On Deactivate', _deactivationEditor!),
      if (_activationEditor == null)
        _automationSummary(
          'On Activate',
          widget.resource.config['activationAutomation'],
        ),
      if (_deactivationEditor == null)
        _automationSummary(
          'On Deactivate',
          widget.resource.config['deactivationAutomation'],
        ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Segments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add segment at start',
            onPressed: () {
              setState(() => _segments.insert(0, _newSegment()));
              _notifyDirty();
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: 'Add segment',
            onPressed: () {
              setState(() => _segments.add(_newSegment()));
              _notifyDirty();
            },
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      if (_segments.isEmpty)
        const Text('No segments defined.')
      else
        for (var index = 0; index < _segments.length; index++)
          _StreamPlanSegmentCard(
            key: _segmentKeys.putIfAbsent(
              _segments[index].id,
              GlobalKey<_StreamPlanSegmentCardState>.new,
            ),
            index: index,
            segment: _segments[index],
            registryFuture: widget.registryFuture,
            resourceOptionsLoader: widget.resourceOptionsLoader,
            onChanged: (segment) {
              setState(() => _segments[index] = segment);
              _notifyDirty();
            },
            onGraphDirty: _notifyDirty,
            onMoveUp: index == 0
                ? null
                : () {
                    setState(() {
                      final segment = _segments.removeAt(index);
                      _segments.insert(index - 1, segment);
                    });
                    _notifyDirty();
                  },
            onMoveDown: index == _segments.length - 1
                ? null
                : () {
                    setState(() {
                      final segment = _segments.removeAt(index);
                      _segments.insert(index + 1, segment);
                    });
                    _notifyDirty();
                  },
            onDelete: () {
              setState(() {
                final removed = _segments.removeAt(index);
                _segmentKeys.remove(removed.id);
              });
              _notifyDirty();
            },
          ),
    ];
    if (!widget.documentMode) {
      return _ResourceForm(
        title: 'Edit stream plan',
        fields: fields,
        onSave: _save,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
          child: Row(
            children: [
              const Icon(Icons.calendar_view_week_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.resource.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: fields,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final config = _savedConfig();
    await widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: config,
        state: widget.resource.state,
      ),
    );
    _savedBaseline = jsonEncode(config);
    _notifyDirty();
  }

  void _notifyDirty() {
    if (!mounted) return;
    final config = _savedConfig();
    final dirty = jsonEncode(config) != _savedBaseline;
    widget.onDocumentChanged?.call(
      ResourceData(
        id: widget.resource.id,
        config: config,
        state: widget.resource.state,
      ),
      dirty,
    );
  }

  JsonMap _savedConfig() {
    final plan = _initialPlan;
    return {
      ...widget.resource.config,
      'name': _name.text.trim(),
      'activationAutomation':
          _activationEditor?.document.toJson() ?? plan.activationAutomation,
      'deactivationAutomation':
          _deactivationEditor?.document.toJson() ?? plan.deactivationAutomation,
      'segments': _segments
          .map(
            (segment) =>
                (_segmentKeys[segment.id]?.currentState?._savedSegment() ??
                        segment)
                    .toJson(),
          )
          .toList(),
    };
  }

  StreamPlanSegmentData _newSegment() => StreamPlanSegmentData(
    id: 'segment-${DateTime.now().microsecondsSinceEpoch}',
    name: 'New segment',
    components: {
      'twitch-stream-info': {'title': '', 'category': ''},
    },
    activationAutomation: emptyInlineAutomation(),
    deactivationAutomation: emptyInlineAutomation(),
  );

  Widget _automationSummary(String label, Object? value) {
    final automation = value is Map
        ? Map<String, dynamic>.from(value)
        : emptyInlineAutomation();
    final graph = automation['graph'];
    final nodes = graph is Map && graph['nodes'] is List
        ? (graph['nodes'] as List).length
        : 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(label),
      subtitle: Text('$nodes automation node${nodes == 1 ? '' : 's'}'),
    );
  }

  Widget _inlineStreamPlanAutomation(
    String label,
    AutomationEditorController editor,
  ) => ExpansionTile(
    key: ValueKey('stream-plan-$label'),
    leading: const Icon(Icons.account_tree_outlined),
    title: Text(label),
    subtitle: Text('${editor.graph.activeSpace!.nodes.length} nodes'),
    children: [
      SizedBox(
        width: 720,
        child: InlineAutomationGraph(
          editor: editor,
          registryFuture: widget.registryFuture!,
          resourceOptionsLoader: widget.resourceOptionsLoader,
        ),
      ),
    ],
  );
}
