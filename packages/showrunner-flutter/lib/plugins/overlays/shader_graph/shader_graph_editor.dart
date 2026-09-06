// ignore_for_file: curly_braces_in_flow_control_structures, prefer_function_declarations_over_variables

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart';

import 'shader_graph_compiler.dart';
import 'shader_graph_model.dart';
import 'shader_node_definitions.dart';

final class ShaderGraphEditorResult {
  const ShaderGraphEditorResult({
    required this.graph,
    required this.glsl,
    required this.uniforms,
    required this.bindings,
  });

  final ShaderGraph graph;
  final String glsl;
  final Map<String, dynamic> uniforms;
  final Map<String, dynamic> bindings;
}

/// Flutter editor for the overlay shader graph.
///
/// `sai_nodes` owns canvas interaction, links, selection, history and
/// clipboard. ShowRunner owns the persisted graph schema and GLSL compiler.
/// That boundary keeps the editor reusable without leaking sai_nodes' runtime
/// model into project files.
class ShaderGraphEditorDialog extends StatefulWidget {
  const ShaderGraphEditorDialog({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  State<ShaderGraphEditorDialog> createState() =>
      _ShaderGraphEditorDialogState();
}

class _ShaderGraphEditorDialogState extends State<ShaderGraphEditorDialog> {
  late final NodeEditorController _controller;
  late final ShaderGraph _initialGraph;
  late ShaderGraph _graph;
  late StreamSubscription<NodeEditorEvent> _events;
  final Map<String, String> _editorToGraphId = {};
  final Map<String, String> _graphToEditorId = {};
  final Set<String> _expandedCategories = {...shaderNodeCategories};
  String? _starter;
  String? _selectedFrameId;
  ShaderGraphCompileResult? _compileResult;
  bool _showGlsl = false;
  bool _showPalette = true;
  bool _showFrames = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initialGraph = _readGraph(widget.config['shaderGraph']);
    _graph = cloneShaderGraph(_initialGraph);
    _controller = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
        enableNodeResize: true,
      ),
      onCallback: (type, message) {
        if (type == CallbackType.error && mounted) {
          setState(
            () => _compileResult = ShaderGraphCompileResult(
              glsl: '',
              errors: [message],
              warnings: const [],
            ),
          );
        }
      },
    );
    _registerPrototypes();
    _events = _controller.eventBus.events.listen(_onEditorEvent);
    _loadGraph(_graph);
  }

  ShaderGraph _readGraph(dynamic value) {
    if (value is Map) return ShaderGraph.fromJson(value);
    return createDefaultShaderGraph();
  }

  void _registerPrototypes() {
    for (final definition in shaderNodeDefinitions) {
      final color = _categoryColor(definition.category);
      _controller.registerNodePrototype(
        NodePrototype(
          idName: definition.id,
          displayName: (_) => definition.name,
          description: (_) => '${definition.category} shader node',
          styleBuilder: (_) => NodeStyle(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          ports: [
            for (final port in definition.inputs) _dataPort(port, input: true),
            for (final port in definition.outputs)
              _dataPort(port, input: false),
          ],
          fields: [
            for (final port in definition.inputs)
              if (port.defaultValue != null)
                _textField(
                  'default.${port.key}',
                  port.label,
                  port.defaultValue!,
                ),
            if ({
              'float_const',
              'vec3_const',
              'uniform_float',
              'uniform_vec2',
              'uniform_vec3',
            }.contains(definition.id))
              _textField(
                'value',
                'Value',
                definition.outputs.first.defaultValue ?? '',
              ),
            if ({
              'uniform_float',
              'uniform_vec2',
              'uniform_vec3',
            }.contains(definition.id)) ...[
              _textField('name', 'Uniform name', ''),
              _textField('bindingSource', 'Binding source (config/state)', ''),
              _textField('bindingPath', 'Binding path', ''),
              _textField('bindingPlugin', 'Binding plugin', ''),
              _textField('bindingState', 'Binding state', ''),
            ],
            if (definition.id == 'color_ramp')
              _textField('rampStops', 'Ramp stops JSON', ''),
          ],
          onExecute: (ports, fields, state, forward, put) async {},
        ),
      );
    }
  }

  PortPrototype _dataPort(ShaderPortDefinition port, {required bool input}) {
    final display = (_) => port.label;
    return switch ((port.type, input)) {
      (ShaderGlslType.float, true) => DataInputPortPrototype<double>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
      (ShaderGlslType.float, false) => DataOutputPortPrototype<double>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
      (ShaderGlslType.vec2, true) => DataInputPortPrototype<_ShaderVec2>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
      (ShaderGlslType.vec2, false) => DataOutputPortPrototype<_ShaderVec2>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
      (ShaderGlslType.vec3, true) => DataInputPortPrototype<_ShaderVec3>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
      (ShaderGlslType.vec3, false) => DataOutputPortPrototype<_ShaderVec3>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
      (ShaderGlslType.vec4, true) => DataInputPortPrototype<_ShaderVec4>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
      (ShaderGlslType.vec4, false) => DataOutputPortPrototype<_ShaderVec4>(
        idName: port.key,
        displayName: display,
        styleBuilder: defaultPortStyleBuilder,
      ),
    };
  }

  FieldPrototype _textField(String id, String label, String defaultData) =>
      FieldPrototype(
        idName: id,
        displayName: (_) => label,
        dataType: String,
        defaultData: defaultData,
        visualizerBuilder: (data) => Text(
          data?.toString() ?? defaultData,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        editorBuilder: (context, removeOverlay, data, setData) {
          var value = data?.toString() ?? defaultData;
          return Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: 240,
              child: TextFormField(
                autofocus: true,
                initialValue: value,
                decoration: InputDecoration(
                  labelText: label,
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Apply',
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      setData(value, eventType: FieldEventType.submit);
                      removeOverlay();
                    },
                  ),
                ),
                onChanged: (next) => value = next,
                onFieldSubmitted: (next) {
                  setData(next, eventType: FieldEventType.submit);
                  removeOverlay();
                },
              ),
            ),
          );
        },
      );

  void _loadGraph(ShaderGraph graph) {
    _loading = true;
    _controller.clear();
    _editorToGraphId.clear();
    _graphToEditorId.clear();
    for (final shaderNode in graph.nodes) {
      final node = _controller.addNode(
        shaderNode.defId,
        offset: Offset(shaderNode.x, shaderNode.y),
      );
      _editorToGraphId[node.id] = shaderNode.id;
      _graphToEditorId[shaderNode.id] = node.id;
      for (final entry in shaderNode.inputDefaults.entries) {
        final field =
            node.fields['default.${entry.key}'] ?? node.fields[entry.key];
        if (field != null) field.data = entry.value.toString();
        final metadata = node.fields[entry.key];
        if (metadata != null && entry.key != 'value')
          metadata.data = entry.value.toString();
      }
    }
    for (final wire in graph.wires) {
      final from = _graphToEditorId[wire.fromNode];
      final to = _graphToEditorId[wire.toNode];
      if (from != null && to != null)
        _controller.addLink(from, wire.fromPort, to, wire.toPort);
    }
    _loading = false;
    if (mounted) setState(() {});
  }

  void _onEditorEvent(NodeEditorEvent event) {
    if (!mounted || _loading) return;
    if (event is AddNodeEvent) {
      final id =
          'shader-${DateTime.now().microsecondsSinceEpoch}-${_editorToGraphId.length}';
      _editorToGraphId[event.node.id] = id;
      _graphToEditorId[id] = event.node.id;
    }
    if (event is RemoveNodeEvent) {
      final graphId = _editorToGraphId.remove(event.node.id);
      if (graphId != null) _graphToEditorId.remove(graphId);
    }
    setState(_syncGraph);
  }

  void _syncGraph() {
    final nodes = <ShaderNodeInstance>[];
    for (final node in _controller.nodes.values) {
      final id = _editorToGraphId[node.id];
      if (id == null) continue;
      final defaults = <String, dynamic>{};
      for (final field in node.fields.values) {
        final key = field.prototype.idName;
        if (key.startsWith('default.')) {
          defaults[key.substring('default.'.length)] = field.data;
        } else if (key == 'value' ||
            key == 'name' ||
            key == 'bindingSource' ||
            key == 'bindingPath' ||
            key == 'bindingPlugin' ||
            key == 'bindingState' ||
            key == 'rampStops') {
          final value = field.data?.toString() ?? '';
          if (value.isNotEmpty) defaults[key] = value;
        }
      }
      nodes.add(
        ShaderNodeInstance(
          id: id,
          defId: node.prototype.idName,
          x: node.offset.dx,
          y: node.offset.dy,
          inputDefaults: defaults,
        ),
      );
    }
    final wires = <ShaderWire>[];
    for (final link in _controller.links.values) {
      final from = _editorToGraphId[link.endpoints.sourceNodeId];
      final to = _editorToGraphId[link.endpoints.targetNodeId];
      if (from == null || to == null) continue;
      wires.add(
        ShaderWire(
          id: link.id,
          fromNode: from,
          fromPort: link.endpoints.sourcePortId,
          toNode: to,
          toPort: link.endpoints.targetPortId,
        ),
      );
    }
    final outputNodeId =
        _graph.outputNodeId != null &&
            nodes.any((node) => node.id == _graph.outputNodeId)
        ? _graph.outputNodeId
        : nodes
              .where((node) => node.defId == 'fragment_output')
              .map((node) => node.id)
              .firstOrNull;
    _graph = ShaderGraph(
      nodes: nodes,
      wires: wires,
      frames: _graph.frames,
      outputNodeId: outputNodeId,
    );
  }

  void _selectStarter(String? id) {
    if (id == null) return;
    _starter = id;
    _graph = createShaderGraphStarter(id);
    _compileResult = null;
    _loadGraph(_graph);
  }

  void _resetGraph() {
    _starter = null;
    _graph = createDefaultShaderGraph();
    _compileResult = null;
    _loadGraph(_graph);
  }

  void _compile() {
    _syncGraph();
    final result = compileShaderGraph(_graph);
    setState(() => _compileResult = result);
  }

  void _autoLayout() {
    _syncGraph();
    final incoming = {for (final node in _graph.nodes) node.id: 0};
    for (final wire in _graph.wires)
      incoming[wire.toNode] = incoming[wire.toNode]! + 1;
    final levels = <String, int>{};
    final pending = <String>[
      for (final node in _graph.nodes)
        if (incoming[node.id] == 0) node.id,
    ];
    while (pending.isNotEmpty) {
      final id = pending.removeAt(0);
      final level = levels[id] ?? 0;
      for (final wire in _graph.wires.where((wire) => wire.fromNode == id)) {
        levels[wire.toNode] = (levels[wire.toNode] ?? 0).clamp(level + 1, 9999);
        incoming[wire.toNode] = incoming[wire.toNode]! - 1;
        if (incoming[wire.toNode] == 0) pending.add(wire.toNode);
      }
    }
    final row = <int, int>{};
    for (final node in _controller.nodes.values) {
      final id = _editorToGraphId[node.id];
      if (id == null) continue;
      final level = levels[id] ?? 0;
      final index = row.update(level, (value) => value + 1, ifAbsent: () => 0);
      node.offset = Offset(80 + level * 280, 80 + index * 150);
    }
    setState(_syncGraph);
    _controller.focusAllNodes();
  }

  void _addFrame() {
    _syncGraph();
    final selected = _controller.selectedNodeIds
        .map((id) => _editorToGraphId[id])
        .whereType<String>()
        .toList();
    if (selected.isEmpty) return;
    final selectedNodes = _graph.nodes
        .where((node) => selected.contains(node.id))
        .toList();
    final left =
        selectedNodes.map((node) => node.x).reduce((a, b) => a < b ? a : b) -
        36;
    final top =
        selectedNodes.map((node) => node.y).reduce((a, b) => a < b ? a : b) -
        56;
    final right =
        selectedNodes.map((node) => node.x).reduce((a, b) => a > b ? a : b) +
        300;
    final bottom =
        selectedNodes.map((node) => node.y).reduce((a, b) => a > b ? a : b) +
        180;
    final frame = ShaderFrame(
      id: 'frame-${DateTime.now().microsecondsSinceEpoch}',
      title: 'Frame ${_graph.frames.length + 1}',
      color: '#7c4dff',
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
      nodeIds: selected,
    );
    setState(() => _graph = _graph.copyWith(frames: [..._graph.frames, frame]));
  }

  @override
  void dispose() {
    _events.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: math.min(
        1320,
        math.max(320, MediaQuery.sizeOf(context).width - 48),
      ),
      height: math.min(
        820,
        math.max(320, MediaQuery.sizeOf(context).height - 48),
      ),
      child: Column(
        children: [
          _toolbar(context),
          Expanded(
            child: Row(
              children: [
                if (_showPalette)
                  SizedBox(width: 220, child: _palette(context)),
                Expanded(child: _canvas(context)),
                if (_showFrames)
                  SizedBox(width: 220, child: _inspector(context)),
              ],
            ),
          ),
          if (_compileResult != null) _compilePanel(context),
        ],
      ),
    ),
  );

  Widget _toolbar(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 18),
          const SizedBox(width: 8),
          const Text(
            'Shader Graph',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _starter,
            hint: const Text('Starter graph'),
            underline: const SizedBox.shrink(),
            items: [
              for (final starter in shaderGraphStarters)
                DropdownMenuItem(value: starter.id, child: Text(starter.name)),
            ],
            onChanged: _selectStarter,
          ),
          IconButton(
            tooltip: 'Reset graph',
            onPressed: _resetGraph,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: 'Add frame from selection',
            onPressed: _addFrame,
            icon: const Icon(Icons.select_all),
          ),
          IconButton(
            tooltip: 'Toggle node palette',
            onPressed: () => setState(() => _showPalette = !_showPalette),
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: 'Toggle frames',
            onPressed: () => setState(() => _showFrames = !_showFrames),
            icon: const Icon(Icons.view_sidebar_outlined),
          ),
          IconButton(
            tooltip: 'Show GLSL',
            onPressed: () => setState(() => _showGlsl = !_showGlsl),
            icon: const Icon(Icons.code),
          ),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: _compile,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Compile & apply'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );

  Widget _palette(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final category in shaderNodeCategories) ...[
          ListTile(
            dense: true,
            title: Text(
              category,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Icon(
              _expandedCategories.contains(category)
                  ? Icons.expand_less
                  : Icons.expand_more,
            ),
            onTap: () => setState(() {
              if (!_expandedCategories.remove(category))
                _expandedCategories.add(category);
            }),
          ),
          if (_expandedCategories.contains(category))
            for (final definition in shaderNodeDefinitions.where(
              (item) => item.category == category,
            ))
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.circle,
                  size: 9,
                  color: _categoryColor(category),
                ),
                title: Text(
                  definition.name,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  final node = _controller.addNode(
                    definition.id,
                    offset: const Offset(120, 120),
                  );
                  _controller.selectNodesById({node.id});
                },
              ),
        ],
      ],
    ),
  );

  Widget _canvas(BuildContext context) => Column(
    children: [
      NodeEditorToolbar(controller: _controller, onAutoLayout: _autoLayout),
      Expanded(
        child: NodeEditorShortcutsWidget(
          controller: _controller,
          onCopy: (context) async {
            await _controller.clipboard.copySelection(context: context);
          },
          onPaste: (context) async {
            await _controller.clipboard.pasteSelection(context: context);
          },
          onCut: (context) async {
            await _controller.clipboard.cutSelection(context: context);
          },
          child: NodeEditorWidget(
            controller: _controller,
            expandToParent: true,
            overlay: () => [
              OverlayData(
                top: 0,
                left: 0,
                right: 0,
                bottom: 0,
                child: _ShaderFramesOverlay(
                  frames: _graph.frames,
                  selectedFrameId: _selectedFrameId,
                  controller: _controller,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _inspector(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Frames', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_graph.frames.isEmpty) const Text('Select nodes and add a frame.'),
        for (final frame in _graph.frames)
          ListTile(
            dense: true,
            selected: _selectedFrameId == frame.id,
            title: Text(frame.title),
            subtitle: Text('${frame.nodeIds.length} nodes'),
            trailing: IconButton(
              tooltip: 'Delete frame',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => setState(
                () => _graph = _graph.copyWith(
                  frames: _graph.frames
                      .where((item) => item.id != frame.id)
                      .toList(),
                ),
              ),
            ),
            onTap: () => setState(() => _selectedFrameId = frame.id),
          ),
        const Divider(),
        const Text('Output', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          _graph.outputNodeId == null
              ? 'Auto-detect Fragment Output'
              : _graph.outputNodeId!,
        ),
        const SizedBox(height: 8),
        Text('Nodes: ${_graph.nodes.length}'),
        Text('Wires: ${_graph.wires.length}'),
        if (_compileResult?.warnings.isNotEmpty == true) ...[
          const Divider(),
          const Text('Warnings', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final warning in _compileResult!.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                warning,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ],
    ),
  );

  Widget _compilePanel(BuildContext context) {
    final result = _compileResult!;
    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(10),
      child: result.errors.isNotEmpty
          ? Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(result.errors.join('\n'))),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: _showGlsl
                      ? SingleChildScrollView(
                          child: SelectableText(
                            result.glsl,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        )
                      : const Text(
                          'Shader compiled successfully. Apply it to the overlay widget?',
                        ),
                ),
                if (!_showGlsl)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      ShaderGraphEditorResult(
                        graph: _graph,
                        glsl: result.glsl,
                        uniforms: collectShaderUniformDefaults(_graph),
                        bindings: collectShaderUniformBindings(_graph),
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
              ],
            ),
    );
  }
}

final class _ShaderVec2 {}

final class _ShaderVec3 {}

final class _ShaderVec4 {}

final class _ShaderFramesOverlay extends StatelessWidget {
  const _ShaderFramesOverlay({
    required this.frames,
    required this.selectedFrameId,
    required this.controller,
  });

  final List<ShaderFrame> frames;
  final String? selectedFrameId;
  final NodeEditorController controller;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        controller.viewportOffsetNotifier,
        controller.viewportZoomNotifier,
      ]),
      builder: (context, child) => CustomPaint(
        painter: _ShaderFramesPainter(
          frames: frames,
          selectedFrameId: selectedFrameId,
          viewportOffset: controller.viewportOffset,
          viewportZoom: controller.viewportZoom,
        ),
      ),
    ),
  );
}

final class _ShaderFramesPainter extends CustomPainter {
  const _ShaderFramesPainter({
    required this.frames,
    required this.selectedFrameId,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final List<ShaderFrame> frames;
  final String? selectedFrameId;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    for (final frame in frames) {
      final bounds = Rect.fromLTWH(
        size.width / 2 + (frame.x + viewportOffset.dx) * viewportZoom,
        size.height / 2 + (frame.y + viewportOffset.dy) * viewportZoom,
        frame.width * viewportZoom,
        frame.height * viewportZoom,
      );
      final selected = frame.id == selectedFrameId;
      final color = _shaderFrameColor(frame.color);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
        Paint()..color = color.withValues(alpha: selected ? 0.08 : 0.035),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = color.withValues(alpha: selected ? 0.9 : 0.42),
      );
      final label = TextPainter(
        text: TextSpan(
          text: frame.title,
          style: TextStyle(
            color: color.withValues(alpha: selected ? 0.95 : 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: math.max(40, bounds.width - 16));
      label.paint(canvas, Offset(bounds.left + 8, bounds.top + 6));
    }
  }

  @override
  bool shouldRepaint(_ShaderFramesPainter oldDelegate) =>
      oldDelegate.frames != frames ||
      oldDelegate.selectedFrameId != selectedFrameId ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

Color _shaderFrameColor(String value) {
  final normalized = value.replaceFirst('#', '').trim();
  final parsed = int.tryParse(
    normalized.length == 6 ? 'ff$normalized' : normalized,
    radix: 16,
  );
  return parsed == null ? const Color(0xff7c4dff) : Color(parsed);
}

Color _categoryColor(String category) => switch (category) {
  'Input' => const Color(0xff2563eb),
  'Math' => const Color(0xff7c3aed),
  'Noise' => const Color(0xff0891b2),
  'Terrain' => const Color(0xff16a34a),
  'Vector' => const Color(0xff0e7490),
  'Color' => const Color(0xffdb2777),
  'Lighting' => const Color(0xffca8a04),
  'Material' => const Color(0xffc2410c),
  'Camera' => const Color(0xff9333ea),
  'Utility' => const Color(0xff64748b),
  'Output' => const Color(0xffdc2626),
  _ => const Color(0xff64748b),
};
