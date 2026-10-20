part of 'showrunner_page.dart';

extension _ShowrunnerDocumentCommands on _ShowRunnerPageState {
  Future<void> _closeTab(WorkspaceId workspace) async {
    if (!_workspaceDocuments.canClose) return;
    if (workspace == WorkspaceIds.graph &&
        _activeAutomationFile != null &&
        _graphEditor.isDirty) {
      if (!await _confirmAutomationClose()) return;
    }
    if (workspace == WorkspaceIds.profiles &&
        !await _profileWorkspaceController.confirmClose()) {
      return;
    }
    final overlayId = WorkspaceIds.overlayResourceId(workspace);
    if (overlayId != null && !await _confirmOverlayClose(overlayId)) return;
    final streamPlanId = WorkspaceIds.streamPlanResourceId(workspace);
    if (streamPlanId != null && !await _confirmStreamPlanClose(streamPlanId)) {
      return;
    }
    if (!_workspaceDocuments.close(workspace)) return;
    if (overlayId != null) _overlayDocuments.close(overlayId);
    if (streamPlanId != null) {
      _streamPlanDocuments.close(streamPlanId);
    }
    _updatePageState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _closeOtherTabs() async {
    final selected = _workspaceDocuments.selectedWorkspace;
    if (!_workspaceDocuments.canCloseOthers) return;
    if (selected != WorkspaceIds.graph &&
        _activeAutomationFile != null &&
        _graphEditor.isDirty &&
        !await _confirmAutomationClose()) {
      return;
    }
    if (selected != WorkspaceIds.profiles &&
        _workspaceDocuments.openWorkspaces.contains(WorkspaceIds.profiles) &&
        !await _profileWorkspaceController.confirmClose()) {
      return;
    }
    for (final workspace in _workspaceDocuments.openWorkspaces.where(
      (item) => item != selected,
    )) {
      final id = WorkspaceIds.overlayResourceId(workspace);
      if (id != null && !await _confirmOverlayClose(id)) return;
    }
    final otherStreamPlanIds = _workspaceDocuments.openWorkspaces
        .where((workspace) => workspace != selected)
        .map(WorkspaceIds.streamPlanResourceId)
        .whereType<String>()
        .where((id) => _streamPlanDocuments.dirty[id] == true)
        .toList();
    for (final id in otherStreamPlanIds) {
      if (!await _confirmStreamPlanClose(id)) return;
    }
    if (!_workspaceDocuments.closeOthers()) return;
    _overlayDocuments.retainOnly(WorkspaceIds.overlayResourceId(selected));
    _streamPlanDocuments.retainOnly(
      WorkspaceIds.streamPlanResourceId(selected),
    );
    _updatePageState(() {});
    unawaited(_persistNavigation());
  }

  Future<bool> _guardDocumentClose(Future<bool> Function() operation) async {
    try {
      return await operation();
    } catch (error) {
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Unable to save document: $error',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
      return false;
    }
  }

  Future<bool> _confirmAutomationClose() => _activeAutomationFile == null
      ? Future.value(true)
      : _guardDocumentClose(
          () => _documents.confirmAutomation(
            _activeAutomationFile!,
            _showAutomationCloseDialog,
          ),
        );

  Future<bool> _confirmAllAutomationClose() async {
    return _guardDocumentClose(
      () => _documents.confirmAllClose((names) async {
        final decision = await showDialog<DocumentCloseDecision>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: Text('Save changes to $names before exiting?'),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(DocumentCloseDecision.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(DocumentCloseDecision.discard),
                child: const Text("Don't Save"),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(DocumentCloseDecision.save),
                child: const Text('Save All'),
              ),
            ],
          ),
        );
        return mounted
            ? decision ?? DocumentCloseDecision.cancel
            : DocumentCloseDecision.cancel;
      }),
    );
  }

  Future<bool> _confirmStreamPlanClose(String id) => _guardDocumentClose(
    () => _documents.confirmResource(
      'StreamPlan',
      id,
      _showAutomationCloseDialog,
    ),
  );

  Future<DocumentCloseDecision> _showAutomationCloseDialog(
    String fileName,
  ) async {
    if (!mounted) return DocumentCloseDecision.cancel;
    final decision = await showDialog<DocumentCloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text('Save changes to $fileName before closing?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(DocumentCloseDecision.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(DocumentCloseDecision.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(DocumentCloseDecision.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return mounted
        ? decision ?? DocumentCloseDecision.cancel
        : DocumentCloseDecision.cancel;
  }

  Future<void> _closeAutomationDocument(String fileName) async {
    final wasActive = _activeAutomationFile == fileName;
    if (!await _guardDocumentClose(
      () => _documents.closeAutomation(fileName, _showAutomationCloseDialog),
    )) {
      return;
    }
    if (wasActive) {
      final replacement = _activeAutomationSession;
      if (replacement == null) {
        _scratchEditor.load(AutomationDocument.empty());
        _graphExecution.setSource(
          ExecutionTraceSource(
            type: 'automation',
            id: _scratchEditor.document.id,
          ),
        );
      } else {
        _loadAutomationSession(replacement);
      }
    }
    if (!mounted) return;
    _updatePageState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _saveSelectedDocument() async {
    final selected = _workspaceDocuments.selectedWorkspace;
    final overlay =
        _overlayDocuments.resources[WorkspaceIds.overlayResourceId(selected)];
    if (overlay != null) {
      await _trySaveOverlayResource(overlay);
      return;
    }
    final plan = _streamPlanDocuments
        .resources[WorkspaceIds.streamPlanResourceId(selected)];
    if (plan != null) {
      await _trySaveStreamPlanResource(plan);
      return;
    }
    await _saveAutomation();
  }

  Future<void> _saveAutomation() async {
    final current = _captureActiveAutomation();
    final fileName = _activeAutomationFile;
    if (fileName == null || current == null) return;
    final saved = await _saveAutomationSession(
      _automationDocuments.find(fileName)!,
      data: current,
      showFeedback: true,
    );
    if (saved && mounted) _updatePageState(() {});
  }

  AutomationDocument? _captureActiveAutomation() =>
      _activeAutomationSession?.data;

  Future<bool> _saveAutomationSession(
    AutomationEditorSession session, {
    AutomationDocument? data,
    bool showFeedback = false,
  }) async {
    final fileName = session.fileName;
    try {
      await _documents.saveAutomation(session, document: data);
      if (showFeedback && mounted) {
        showShowRunnerFeedback(
          context,
          'Saved $fileName',
          severity: ShowRunnerFeedbackSeverity.success,
        );
      }
      return true;
    } catch (error) {
      if (showFeedback && mounted) {
        showShowRunnerFeedback(
          context,
          'Unable to save automation: $error',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
      return false;
    }
  }

  Future<void> _frameSelectionFromCommand() async {
    final titleController = TextEditingController(text: 'Frame');
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Name annotation'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Annotation title',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(titleController.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (!mounted || title == null || title.trim().isEmpty) return;
      final graph = _graphEditor.graph;
      final scene = GraphSceneBuilder().build(graph);
      final bounds = graph.selection.nodes
          .map((id) => scene.nodes[id]?.geometry.bounds)
          .whereType<GraphRect>();
      if (bounds.isNotEmpty) {
        graph.createFrameFromSelection(
          bounds.reduce((a, b) => a.union(b)).inflate(24),
          title: title.trim(),
        );
      }
    } finally {
      titleController.dispose();
    }
  }

  Future<void> _saveAll() async {
    await _guardDocumentClose(() async {
      await _documents.saveAll();
      return true;
    });
    if (mounted) _updatePageState(() {});
  }

  Future<bool> _trySaveStreamPlanResource(ResourceData resource) async {
    try {
      await _saveStreamPlanResource(resource);
      return true;
    } catch (error) {
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Unable to save stream plan: $error',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
      return false;
    }
  }

  Future<bool> _trySaveOverlayResource(ResourceData resource) async {
    try {
      await _saveOverlayResource(resource);
      return true;
    } catch (error) {
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Unable to save overlay: $error',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
      return false;
    }
  }

  Future<bool> _confirmOverlayClose(String id) => _guardDocumentClose(
    () => _documents.confirmResource('Overlay', id, _showAutomationCloseDialog),
  );
}
