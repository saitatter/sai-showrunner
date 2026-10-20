part of 'showrunner_page.dart';

extension _ShowrunnerProjectCommands on _ShowRunnerPageState {
  Future<void> _openAutomation(
    AutomationDocument automation,
    String fileName,
  ) async {
    if (!WorkspaceNavigationSnapshot.isSafeAutomationFileName(fileName)) return;
    _captureActiveAutomation();
    final session = _automationDocuments.open(automation, fileName);
    _loadAutomationSession(session);
    if (!mounted) return;
    _updatePageState(() {
      _workspaceDocuments.open(WorkspaceIds.graph);
      _workspaceDocuments.select(WorkspaceIds.graph);
    });
    showShowRunnerFeedback(
      context,
      'Loaded $fileName into the graph editor',
      severity: ShowRunnerFeedbackSeverity.info,
    );
  }

  Future<void> _selectAutomationDocument(String fileName) async {
    final session = _automationDocuments.find(fileName);
    if (session == null || session.fileName == _activeAutomationFile) {
      if (session != null) _openDestination(WorkspaceIds.graph);
      return;
    }
    _captureActiveAutomation();
    if (!_automationDocuments.activate(fileName)) return;
    _loadAutomationSession(session);
    if (!mounted) return;
    _updatePageState(() {
      _workspaceDocuments.open(WorkspaceIds.graph);
      _workspaceDocuments.select(WorkspaceIds.graph);
    });
  }

  void _loadAutomationSession(AutomationEditorSession session) {
    if (_disposed) return;
    _graphExecution.setSource(
      ExecutionTraceSource(type: 'automation', id: session.fileName),
    );
  }

  void _reorderAutomationDocument(int oldPosition, int newPosition) {
    if (!_automationDocuments.reorder(oldPosition, newPosition)) return;
    _updatePageState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _createAutomation({bool starterOnly = false}) async {
    final selection =
        await showDialog<({String name, AutomationStarter? starter})>(
          context: context,
          builder: (context) => NewAutomationDialog(starterOnly: starterOnly),
        );
    if (!mounted) return;
    if (selection == null) return;
    _captureActiveAutomation();
    final fileName = 'automation-${DateTime.now().millisecondsSinceEpoch}.yaml';
    final starter = selection.starter;
    final base = starter?.automation ?? AutomationDocument.empty();
    final automation = base.withMetadata({
      ...base.metadata,
      'name': selection.name,
    });
    await AutomationRepository(
      File('${widget.dataService.userDirectory.path}/automations/$fileName'),
    ).save(automation);
    final session = _automationDocuments.open(automation, fileName);
    _loadAutomationSession(session);
    if (!mounted) return;
    _updatePageState(() {
      _workspaceDocuments.open(WorkspaceIds.graph);
      _workspaceDocuments.select(WorkspaceIds.graph);
      _projectCatalogRevision++;
    });
    showShowRunnerFeedback(
      context,
      'Created ${selection.name}',
      severity: ShowRunnerFeedbackSeverity.success,
    );
  }

  Future<void> _createProfile() async {
    final name = await showShowRunnerNameDialog(
      context,
      title: 'New profile',
      initialName: 'New Profile',
    );
    if (name == null || !mounted) return;
    if (!await _profileWorkspaceController.confirmClose() || !mounted) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'profile_$timestamp.yaml';
    final emptyAutomation = AutomationDocument.empty();
    final profile = ShowRunnerProfile(
      name: name,
      activationMode: 'toggle',
      triggers: [],
      activationCondition: {},
      activationAutomation: emptyAutomation,
      deactivationAutomation: emptyAutomation,
    );
    await ProfileRepository(
      File('${widget.dataService.userDirectory.path}/profiles/$fileName'),
    ).save(profile);
    if (!mounted) return;
    await _profileWorkspaceController.reloadEntries();
    if (!mounted) return;
    await _profileWorkspaceController.openProfile(fileName);
    if (!mounted) return;
    _onProjectCatalogChanged();
    _openDestination(WorkspaceIds.profiles);
    showShowRunnerFeedback(
      context,
      'Created $name',
      severity: ShowRunnerFeedbackSeverity.success,
    );
  }

  Future<void> _createResource(String resourceType) async {
    final definition = createDefaultResourceEditorRegistry().find(resourceType);
    if (definition == null) return;
    final name = await showShowRunnerNameDialog(
      context,
      title: 'New ${definition.displayName}',
      initialName: definition.displayName,
    );
    if (name == null || !mounted) return;
    final resource = ResourceData(
      id: 'resource-${DateTime.now().microsecondsSinceEpoch}',
      config: definition.defaultConfig(name),
    );
    await ResourceRepository(
      Directory(
        '${widget.dataService.userDirectory.path}/${definition.storageDirectory}',
      ),
      resourceType: resourceType,
      secretSettings: widget.dataService.secretSettingsStore,
    ).save(resource);
    if (resourceType == 'Variable') await _variableRuntime.reload();
    if (!mounted) return;
    _onProjectCatalogChanged();
    _openResource(resource, resourceType);
    showShowRunnerFeedback(
      context,
      'Created $name',
      severity: ShowRunnerFeedbackSeverity.success,
    );
  }

  Future<void> _renameAutomationEntry(String fileName, String name) async {
    if (!WorkspaceNavigationSnapshot.isSafeAutomationFileName(fileName)) return;
    final file = File(
      '${widget.dataService.userDirectory.path}/automations/$fileName',
    );
    final automation = await AutomationRepository(file).load();
    if (automation == null) return;
    await AutomationRepository(
      file,
    ).save(automation.withMetadata({...automation.metadata, 'name': name}));
    if (!mounted) return;
    _updatePageState(() => _projectCatalogRevision++);
  }

  Future<void> _renameProfileEntry(String fileName, String name) async {
    if (!WorkspaceNavigationSnapshot.isSafeAutomationFileName(fileName)) return;
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/$fileName',
    );
    final profile = await ProfileRepository(file).load();
    if (profile == null) return;
    await ProfileRepository(file).save(
      ShowRunnerProfile(
        name: name,
        activationMode: profile.activationMode,
        triggers: profile.triggers,
        activationCondition: profile.activationCondition,
        activationAutomation: profile.activationAutomation,
        deactivationAutomation: profile.deactivationAutomation,
        extra: profile.extra,
      ),
    );
    if (!mounted) return;
    _updatePageState(() => _projectCatalogRevision++);
  }

  Future<void> _deleteProfileEntry(String fileName) async {
    if (!WorkspaceNavigationSnapshot.isSafeAutomationFileName(fileName)) return;
    final profileController = _profileWorkspaceController;
    if (profileController.activeProfileFile == fileName &&
        !await profileController.confirmClose()) {
      return;
    }
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/$fileName',
    );
    if (await file.exists()) await file.delete();
    if (profileController.activeProfileFile == fileName) {
      await profileController.reloadEntries();
    }
    if (!mounted) return;
    _updatePageState(() => _projectCatalogRevision++);
  }

  Future<void> _renameResourceEntry(
    ResourceData resource,
    String resourceType,
    String name,
  ) async {
    if (!WorkspaceNavigationSnapshot.isSafeResourceId(resource.id)) return;
    final definition = createDefaultResourceEditorRegistry().find(resourceType);
    if (definition == null) return;
    final updated = ResourceData(
      id: resource.id,
      config: {...resource.config, 'name': name},
      state: resource.state,
    );
    final repository = ResourceRepository(
      Directory(
        '${widget.dataService.userDirectory.path}/${definition.storageDirectory}',
      ),
      resourceType: resourceType,
      secretSettings: widget.dataService.secretSettingsStore,
    );
    await repository.save(updated);
    if (resourceType == 'Dashboard') {
      await repository.save(
        await DashboardCloudSyncService(
          dataService: widget.dataService,
        ).synchronize(updated),
      );
    }
    if (!mounted) return;
    _updatePageState(() => _projectCatalogRevision++);
  }

  Future<void> _deleteResourceEntry(
    ResourceData resource,
    String resourceType,
  ) async {
    if (!WorkspaceNavigationSnapshot.isSafeResourceId(resource.id)) return;
    if (!await _guardDocumentClose(
      () => _documents.deleteResource(
        resource,
        resourceType,
        _showAutomationCloseDialog,
      ),
    )) {
      return;
    }
    final workspace = switch (resourceType) {
      'Overlay' => WorkspaceIds.overlay(resource.id),
      'StreamPlan' => WorkspaceIds.streamPlan(resource.id),
      _ => null,
    };
    if (workspace != null) {
      if (!_workspaceDocuments.canClose) {
        _workspaceDocuments.open(WorkspaceIds.home);
      }
      _workspaceDocuments.close(workspace);
    }
    if (!mounted) return;
    _updatePageState(() => _projectCatalogRevision++);
  }

  Future<void> _deleteAutomation(String fileName) async {
    if (!WorkspaceNavigationSnapshot.isSafeAutomationFileName(fileName)) return;
    if (!await _guardDocumentClose(
      () => _documents.deleteAutomation(fileName, _showAutomationCloseDialog),
    )) {
      return;
    }
    if (!mounted) return;
    final replacement = _activeAutomationSession;
    if (replacement != null) {
      _loadAutomationSession(replacement);
    } else {
      _graphExecution.setSource(
        ExecutionTraceSource(
          type: 'automation',
          id: _scratchEditor.document.id,
        ),
      );
    }
    _updatePageState(() => _projectCatalogRevision++);
    unawaited(_persistNavigation());
  }
}
