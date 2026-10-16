import 'dart:async';
import 'package:flutter/material.dart';
import '../../components/data_inputs/resource_schema.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../controller/automation_editor_controller.dart';
import 'automation_graph_workspace.dart';

class InlineAutomationGraph extends StatefulWidget {
  const InlineAutomationGraph({
    super.key,
    required this.editor,
    required this.registryFuture,
    this.resourceOptionsLoader,
    this.height = 600,
  });
  final AutomationEditorController editor;
  final Future<DartPluginRegistry> registryFuture;
  final ResourceOptionsLoader? resourceOptionsLoader;
  final double height;
  @override
  State<InlineAutomationGraph> createState() => _InlineAutomationGraphState();
}

class _InlineAutomationGraphState extends State<InlineAutomationGraph> {
  int generation = 0;
  Object? error;
  @override
  void initState() {
    super.initState();
    unawaited(_bind());
  }

  @override
  void didUpdateWidget(InlineAutomationGraph old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor ||
        old.registryFuture != widget.registryFuture) {
      unawaited(_bind());
    }
  }

  Future<void> _bind() async {
    final token = ++generation;
    try {
      final registry = await widget.registryFuture;
      if (!mounted || token != generation) return;
      widget.editor.bindRegistry(registry);
      setState(() => error = null);
    } catch (exception) {
      if (mounted && token == generation) setState(() => error = exception);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: error == null
        ? AutomationGraphWorkspace(
            editor: widget.editor,
            resourceOptionsLoader: widget.resourceOptionsLoader,
          )
        : Center(child: Text('Unable to load graph contracts: $error')),
  );
}
