import 'dart:async';
import 'package:flutter/material.dart';
import '../../components/data_inputs/resource_schema.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../controller/automation_editor_controller.dart';
import 'automation_graph_workspace.dart';
import 'graph_execution_trace_scope.dart';
import '../execution/showrunner_execution_visual_adapter.dart';
import '../../runtime/execution_trace.dart';
import '../../runtime/expression.dart';
import '../runtime/graph_execution_engine.dart';
import '../domain/automation_document.dart';

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
  ExecutionTraceService? traceService;
  GraphExecutionEngine? engine;
  ShowrunnerExecutionVisualAdapter? execution;
  @override
  void initState() {
    super.initState();
    widget.editor.addListener(_editorChanged);
    unawaited(_bind());
  }

  @override
  void didUpdateWidget(InlineAutomationGraph old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_editorChanged);
      widget.editor.addListener(_editorChanged);
      _syncExecution();
    }
    if (old.editor != widget.editor ||
        old.registryFuture != widget.registryFuture) {
      unawaited(_bind());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = GraphExecutionTraceScope.maybeOf(context);
    final service = scope?.service;
    engine = scope?.engine;
    if (service != traceService) {
      traceService = service;
      _syncExecution();
    }
  }

  void _editorChanged() {
    if (execution?.documentId != widget.editor.graph.document.id &&
        traceService != null) {
      _syncExecution();
      if (mounted) setState(() {});
    }
  }

  void _syncExecution() {
    execution?.dispose();
    final id = widget.editor.graph.document.id;
    execution = traceService == null
        ? null
        : ShowrunnerExecutionVisualAdapter(
            service: traceService!,
            source: ExecutionTraceSource(type: 'automation', id: id),
            documentId: id,
          );
  }

  Future<void> _run(
    AutomationDocument document, {
    String? nodeId,
    String? spaceId,
  }) async {
    final registry = await widget.registryFuture;
    if (!mounted) return;
    await engine!.executeWithRegistry(
      automation: document,
      context: EvaluationContext(),
      registry: registry,
      entryNodeId: nodeId,
      entrySpaceId: spaceId ?? mainAutomationSpace,
      traceMode: ExecutionTraceMode.test,
      traceSource: ExecutionTraceSource(type: 'inline-test', id: document.id),
    );
  }

  @override
  void dispose() {
    widget.editor.removeListener(_editorChanged);
    execution?.dispose();
    super.dispose();
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
            execution: execution,
            onRun: engine == null ? null : _run,
            onRunNode: engine == null
                ? null
                : (nodeId) => _run(
                    widget.editor.document,
                    nodeId: nodeId,
                    spaceId: widget.editor.graph.activeSpaceId,
                  ),
            resourceOptionsLoader: widget.resourceOptionsLoader,
          )
        : Center(child: Text('Unable to load graph contracts: $error')),
  );
}
