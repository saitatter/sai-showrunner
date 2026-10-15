part of '../main.dart';

extension _ShowrunnerDocumentCommands on _ShowRunnerPageState {
  Future<void> _closeTab(WorkspaceId workspace) async {
    if (!_workspaceDocuments.canClose) return;
    if (workspace == WorkspaceIds.graph &&
        _activeAutomationFile != null &&
        _graphEditor.documentDirty.value) {
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
        _graphEditor.documentDirty.value &&
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

  Future<bool> _confirmAutomationClose() async {
    _captureActiveAutomation();
    final session = _activeAutomationSession;
    if (session == null || !session.dirty) return true;
    final decision = await _showAutomationCloseDialog(session.fileName);
    if (!mounted || decision == null || decision == _CloseDecision.cancel) {
      return false;
    }
    if (decision == _CloseDecision.save) {
      return _saveAutomationSession(session);
    }
    return true;
  }

  Future<bool> _confirmAllAutomationClose() async {
    _captureActiveAutomation();
    final dirtyAutomations = _automationDocuments.documents
        .where((document) => document.dirty)
        .toList();
    final dirtyStreamPlans = _streamPlanDocuments.dirty.entries
        .where((entry) => entry.value)
        .map((entry) => _streamPlanDocuments.resources[entry.key])
        .whereType<ResourceData>()
        .toList();
    if (dirtyAutomations.isEmpty && dirtyStreamPlans.isEmpty) return true;
    final dirtyNames = [
      ...dirtyAutomations.map((document) => document.fileName),
      ...dirtyStreamPlans.map((resource) => resource.name),
    ];
    final decision = await showDialog<_CloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          'Save changes to ${dirtyNames.join(', ')} before exiting?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.save),
            child: const Text('Save All'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null || decision == _CloseDecision.cancel) {
      return false;
    }
    if (decision == _CloseDecision.save) {
      for (final session in dirtyAutomations) {
        if (!await _saveAutomationSession(session)) return false;
      }
      for (final resource in dirtyStreamPlans) {
        if (!await _trySaveStreamPlanResource(resource)) return false;
      }
    }
    return true;
  }

  Future<bool> _confirmStreamPlanClose(String resourceId) async {
    final resource = _streamPlanDocuments.resources[resourceId];
    if (resource == null || _streamPlanDocuments.dirty[resourceId] != true) {
      return true;
    }
    final decision = await showDialog<_CloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text('Save changes to ${resource.name} before closing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null || decision == _CloseDecision.cancel) {
      return false;
    }
    if (decision == _CloseDecision.save) {
      return _trySaveStreamPlanResource(resource);
    }
    return true;
  }

  Future<_CloseDecision?> _showAutomationCloseDialog(String fileName) {
    return showDialog<_CloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text('Save changes to $fileName before closing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeAutomationDocument(String fileName) async {
    final session = _automationDocuments.find(fileName);
    if (session == null) return;
    _captureActiveAutomation();
    if (session.dirty) {
      final decision = await _showAutomationCloseDialog(fileName);
      if (!mounted || decision == null || decision == _CloseDecision.cancel) {
        return;
      }
      if (decision == _CloseDecision.save &&
          !await _saveAutomationSession(session)) {
        return;
      }
    }
    final wasActive = _activeAutomationFile == fileName;
    _automationDocuments.close(fileName);
    if (wasActive) {
      final replacement = _activeAutomationSession;
      if (replacement == null) {
        _graphEditor.loadAutomation(const AutomationData());
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

  AutomationData? _captureActiveAutomation() {
    final original = _activeAutomation;
    if (original == null) return null;
    final current = _graphEditor.toAutomation(original);
    _automationDocuments.updateActive(current);
    return current;
  }

  Future<bool> _saveAutomationSession(
    AutomationDocumentSession session, {
    AutomationData? data,
    bool showFeedback = false,
  }) async {
    final saved = data ?? session.data;
    final fileName = session.fileName;
    try {
      final issues = validateAutomationGraph(saved);
      if (issues.isNotEmpty) {
        throw FormatException(
          'Automation graph is invalid: ${issues.join(' ')}',
        );
      }
      await AutomationRepository(
        File('${widget.dataService.userDirectory.path}/automations/$fileName'),
      ).save(saved);
      _automationDocuments.markSaved(session.fileName, saved);
      if (session.fileName == _activeAutomationFile) {
        _graphEditor.markDocumentClean();
      }
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
      _graphEditor.frameSelection(title: title.trim());
    } finally {
      titleController.dispose();
    }
  }

  Future<void> _saveAll() async {
    _captureActiveAutomation();
    for (final session in _automationDocuments.documents) {
      if (session.dirty && !await _saveAutomationSession(session)) return;
    }
    for (final entry in _overlayDocuments.dirty.entries.toList()) {
      final resource = _overlayDocuments.resources[entry.key];
      if (entry.value &&
          resource != null &&
          !await _trySaveOverlayResource(resource)) {
        return;
      }
    }
    for (final entry in _streamPlanDocuments.dirty.entries.toList()) {
      final resource = _streamPlanDocuments.resources[entry.key];
      if (entry.value &&
          resource != null &&
          !await _trySaveStreamPlanResource(resource)) {
        return;
      }
    }
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

  Future<bool> _confirmOverlayClose(String id) async {
    final resource = _overlayDocuments.resources[id];
    if (resource == null || _overlayDocuments.dirty[id] != true) return true;
    final decision = await _showAutomationCloseDialog(resource.name);
    if (!mounted || decision == null || decision == _CloseDecision.cancel) {
      return false;
    }
    if (decision == _CloseDecision.save) {
      return _trySaveOverlayResource(resource);
    }
    return true;
  }

  Future<bool> _confirmAllResourceClose() async {
    for (final id in _overlayDocuments.resources.keys.toList()) {
      if (!await _confirmOverlayClose(id)) return false;
    }
    for (final id in _streamPlanDocuments.resources.keys.toList()) {
      if (!await _confirmStreamPlanClose(id)) return false;
    }
    return true;
  }
}
