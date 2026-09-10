part of '../showrunner_graph_editor.dart';

String _nodePresentationTitle(ShowRunnerGraphEditor editor, String id) =>
    editor.nodeTitle(id);

JsonMap _nodePresentationData(ShowRunnerGraphEditor editor, String id) =>
    editor.nodeData(id);

/// ShowRunner-specific node presentation and configuration projection.
///
/// `sai_nodes` owns the generic node model and canvas. This extension keeps
/// plugin names, badges, colors, icons, and persisted configuration outside
/// that generic package.
extension ShowRunnerGraphEditorNodePresentation on ShowRunnerGraphEditor {
  String nodeTitle(String editorNodeId) =>
      (_variableEditorIds.contains(editorNodeId) &&
          _nodeDataByEditorId[editorNodeId]?['name'] is String &&
          (_nodeDataByEditorId[editorNodeId]!['name'] as String)
              .trim()
              .isNotEmpty)
      ? (_nodeDataByEditorId[editorNodeId]!['name'] as String).trim()
      : _nodeTitles[editorNodeId] ??
            controller.nodes[editorNodeId]?.customTitle ??
            _prototypeTitles[controller
                .nodes[editorNodeId]
                ?.prototype
                .idName] ??
            controller.nodes[editorNodeId]?.prototype.idName ??
            '';

  /// The desktop reference renders the plugin/operation identity below the
  /// node title. Keep that information in the editor adapter instead of
  /// making the generic sai_nodes package know about ShowRunner semantics.
  String nodeSubtitle(String editorNodeId) {
    final node = controller.nodes[editorNodeId];
    if (node == null) return '';
    final data = _nodeDataByEditorId[editorNodeId] ?? const <String, dynamic>{};
    final type = node.prototype.idName;
    if (_variableEditorIds.contains(editorNodeId)) {
      final variableType = data['type']?.toString();
      return variableType == null || variableType.isEmpty
          ? 'Variable'
          : '$variableType variable';
    }
    if (type.startsWith('trigger.')) {
      final parts = type.split('.');
      if (parts.length >= 3) {
        final plugin = _registry.findPlugin(parts[1]);
        return '${plugin?.name ?? parts[1]} / ${parts.sublist(2).join('.')}';
      }
    }
    final plugin = data['plugin']?.toString();
    final action = data['action']?.toString();
    if (plugin != null &&
        plugin.isNotEmpty &&
        action != null &&
        action.isNotEmpty) {
      return '${_registry.findPlugin(plugin)?.name ?? plugin} / $action';
    }
    return switch (type) {
      'if' => 'condition',
      'switch' => 'branch',
      'for' || 'forEach' || 'while' => 'flow control',
      'break' || 'continue' || 'return' => 'flow control',
      _ when type.startsWith('subgraphCall:') => 'subgraph call',
      _ => '',
    };
  }

  String? nodeBadge(String editorNodeId) {
    final node = controller.nodes[editorNodeId];
    if (node == null) return null;
    final type = node.prototype.idName.toLowerCase();
    final data = _nodeDataByEditorId[editorNodeId];
    if (data?['plugin'] != null && data?['action'] != null) {
      final plugin = data!['plugin'].toString();
      final action = data['action'].toString();
      if (_registry.findAction(plugin, action) == null) return 'Missing';
      if (_isCoreConversionNodeType(node.prototype.idName)) {
        return 'Convert';
      }
      if (plugin.toLowerCase() == 'showrunner' &&
          (action.toLowerCase().contains('queue') ||
              action.toLowerCase() == 'skip')) {
        return 'Queue';
      }
    }
    if (type.startsWith('trigger.')) return 'Trigger';
    if (type.startsWith('variable.')) return 'Variable';
    if (type.startsWith('subgraphcall:')) return 'Subgraph';
    return null;
  }

  List<(String, String)> nodeConfigLinesProjection(String editorNodeId) {
    final lines = <(String, String)>[];
    final data = _nodeDataByEditorId[editorNodeId] ?? const <String, dynamic>{};
    if (_variableEditorIds.contains(editorNodeId)) {
      final name = data['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        lines.add(('name', name));
      }
      if (data['value'] != null) {
        lines.add(('value', _summarizeGraphValue(data['value'])));
      }
      return lines;
    }
    final config = data['config'];
    if (config is! Map) return lines;
    for (final entry in config.entries) {
      if (lines.length >= 4) break;
      if (entry.value == null) continue;
      lines.add((entry.key.toString(), _summarizeGraphValue(entry.value)));
    }
    if (config.length > lines.length) {
      lines.add(('â€¦', '+${config.length - lines.length} more'));
    }
    return lines;
  }

  IconData nodeIcon(String editorNodeId) {
    final node = controller.nodes[editorNodeId];
    if (node == null) return Icons.extension_outlined;
    final type = node.prototype.idName.toLowerCase();
    final data = _nodeDataByEditorId[editorNodeId];
    if (data?['plugin'] != null && data?['action'] != null) {
      if (_registry.findAction(
            data!['plugin'].toString(),
            data['action'].toString(),
          ) ==
          null) {
        return Icons.error_outline;
      }
      if (_isCoreConversionNodeType(node.prototype.idName)) {
        return Icons.swap_horizontal_circle_outlined;
      }
    }
    if (type.startsWith('trigger.')) return Icons.bolt;
    if (type.startsWith('variable.')) return Icons.data_object;
    if (type.startsWith('subgraphcall:')) return Icons.functions;
    return switch (type) {
      'if' => Icons.call_split,
      'switch' => Icons.alt_route,
      'for' || 'foreach' => Icons.repeat,
      'while' => Icons.sync,
      'break' => Icons.exit_to_app,
      'continue' => Icons.skip_next,
      'return' => Icons.keyboard_return,
      _ => Icons.extension_outlined,
    };
  }

  Color nodeAccent(String editorNodeId) {
    final node = controller.nodes[editorNodeId];
    if (node == null) return const Color(0xff94a3b8);
    final type = node.prototype.idName.toLowerCase();
    final data = _nodeDataByEditorId[editorNodeId];
    if (data?['plugin'] != null && data?['action'] != null) {
      final plugin = data!['plugin'].toString().toLowerCase();
      final action = data['action'].toString().toLowerCase();
      if (_registry.findAction(plugin, action) == null) {
        return const Color(0xffef5350);
      }
      if (_isCoreConversionNodeType(node.prototype.idName)) {
        return const Color(0xff4dd0e1);
      }
      if (plugin == 'showrunner' &&
          (action.contains('queue') || action == 'skip')) {
        return const Color(0xffffcf5a);
      }
    }
    return switch (type) {
      _ when type.startsWith('trigger.') => const Color(0xffe9aaff),
      'if' => const Color(0xff64b5f6),
      'switch' => const Color(0xff7c4dff),
      'for' || 'foreach' => const Color(0xff68d391),
      'while' => const Color(0xff4db6ac),
      'break' || 'continue' => const Color(0xffef9a9a),
      'return' => const Color(0xffffab91),
      _ when type.startsWith('variable.') => const Color(0xff90a4ae),
      _ when type.startsWith('subgraphcall:') => const Color(0xff4dd0e1),
      _ => const Color(0xff7d32d4),
    };
  }

  String? customNodeTitle(String editorNodeId) =>
      _nodeTitles[editorNodeId] ?? controller.nodes[editorNodeId]?.customTitle;

  JsonMap nodeData(String editorNodeId) => Map.unmodifiable(
    _nodeDataByEditorId[editorNodeId] ?? const <String, dynamic>{},
  );

  JsonMap variableNodeData(String editorNodeId) => isVariableNode(editorNodeId)
      ? nodeData(editorNodeId)
      : const <String, dynamic>{};

  JsonMap nodeConfig(String editorNodeId) {
    final config = nodeData(editorNodeId)['config'];
    return config is Map
        ? Map<String, dynamic>.from(config)
        : <String, dynamic>{};
  }

  JsonMap nodeResultMapping(String editorNodeId) {
    final mapping = nodeData(editorNodeId)['resultMapping'];
    return mapping is Map
        ? Map<String, dynamic>.from(mapping)
        : <String, dynamic>{};
  }

  void updateNodeConfig(String editorNodeId, JsonMap config) {
    if (!controller.nodes.containsKey(editorNodeId)) return;
    _nodeDataByEditorId.putIfAbsent(editorNodeId, () => {});
    _nodeDataByEditorId[editorNodeId]!['config'] = Map<String, dynamic>.from(
      config,
    );
    nodeRevision.value++;
  }

  void updateNodeResultMapping(String editorNodeId, JsonMap mapping) {
    if (!controller.nodes.containsKey(editorNodeId)) return;
    _nodeDataByEditorId.putIfAbsent(editorNodeId, () => {});
    _nodeDataByEditorId[editorNodeId]!['resultMapping'] =
        Map<String, dynamic>.from(mapping);
    nodeRevision.value++;
  }

  void updateTriggerNodeData(
    String editorNodeId, {
    required JsonMap config,
    required bool stop,
  }) {
    if (!isTriggerNode(editorNodeId)) return;
    _nodeDataByEditorId.putIfAbsent(editorNodeId, () => {});
    _nodeDataByEditorId[editorNodeId]!
      ..['config'] = Map<String, dynamic>.from(config)
      ..['stop'] = stop;
    nodeRevision.value++;
  }
}
