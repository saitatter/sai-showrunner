part of 'main.dart';

extension _ShowRunnerPageNavigation on _ShowRunnerPageState {
  Future<void> _restoreNavigation() async {
    try {
      final settings = await widget.dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      final hasRestoredWorkspaceTabs = settings.containsKey(
        'openWorkspaceTabs',
      );
      final restoredTabs = settings['openWorkspaceTabs'];
      var tabs = restoredTabs is List
          ? _ShowRunnerPageState._workspaceIdsFromSettings(restoredTabs)
          : hasRestoredWorkspaceTabs
          ? <WorkspaceId>[]
          : <WorkspaceId>[WorkspaceIds.home];
      final restoredSelected = settings['selectedWorkspace'];
      final restoredResourceType = settings['selectedResourceType'];
      final restoredResourceId = settings['selectedResourceId'];
      final selected = restoredSelected is String
          ? _ShowRunnerPageState._workspaceIdFromSettings(restoredSelected)
          : hasRestoredWorkspaceTabs
          ? null
          : WorkspaceIds.home;
      if (widget.showGraphEditor) {
        await _restoreAutomationDocuments(settings);
      }
      await _restoreOverlayDocuments(tabs);
      tabs = tabs
          .where(
            (tab) =>
                !WorkspaceIds.isOverlay(tab) ||
                _openOverlayResources.containsKey(
                  WorkspaceIds.overlayResourceId(tab),
                ),
          )
          .toList(growable: false);
      if (!mounted) return;
      _updatePageState(() {
        _workspaceDocuments.restore(openWorkspaces: tabs, selected: selected);
        _selectedResourceType = restoredResourceType is String
            ? restoredResourceType
            : null;
        _selectedResourceId = restoredResourceId is String
            ? restoredResourceId
            : null;
        _restoredNavigation = true;
      });
    } catch (_) {
      if (mounted) _updatePageState(() => _restoredNavigation = true);
    }
  }

  Future<void> _restoreOverlayDocuments(Iterable<WorkspaceId> tabs) async {
    final repository = ResourceRepository(
      Directory('${widget.dataService.userDirectory.path}/overlays'),
      resourceType: 'Overlay',
      secretSettings: widget.dataService.secretSettingsStore,
    );
    for (final tab in tabs.where(WorkspaceIds.isOverlay)) {
      final resourceId = WorkspaceIds.overlayResourceId(tab);
      if (resourceId == null) continue;
      final resource = await repository.load(resourceId);
      if (resource != null) _openOverlayResources[resource.id] = resource;
    }
  }

  Future<void> _initializeNavigationAndFirstRun() async {
    await _restoreNavigation();
    await _openFirstRunSetupIfNeeded();
  }

  Future<void> _restoreAutomationDocuments(
    Map<String, dynamic> settings,
  ) async {
    final restored = settings['openAutomationTabs'];
    if (restored is! List) return;
    final fileNames = restored
        .whereType<String>()
        .where(_ShowRunnerPageState._isSafeAutomationFileName)
        .toSet();
    for (final fileName in fileNames) {
      try {
        final automation = await AutomationRepository(
          File(
            '${widget.dataService.userDirectory.path}/automations/$fileName',
          ),
        ).load();
        if (automation != null) {
          _automationDocuments.open(automation, fileName);
        }
      } catch (_) {
        // A deleted or invalid resource should not prevent the rest of the
        // desktop session from being restored.
      }
    }
    final selected = settings['selectedAutomationTab'];
    if (selected is String && _automationDocuments.find(selected) != null) {
      _automationDocuments.activate(selected);
    }
    final active = _activeAutomationSession;
    if (active != null) {
      _graphEditor.loadAutomation(active.data);
      _graphEditor.restoreDocumentDirty(active.dirty);
    }
  }

  Future<bool> _activateProfileResource(
    String requestedProfileId,
    String activation,
    EvaluationContext context,
  ) async {
    final profileId = requestedProfileId.endsWith('.yaml')
        ? requestedProfileId.substring(0, requestedProfileId.length - 5)
        : requestedProfileId;
    if (!_ShowRunnerPageState._isSafeResourceId(profileId)) return false;
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/$profileId.yaml',
    );
    final repository = ProfileRepository(file);
    final profile = await repository.load();
    if (profile == null) return false;
    final runtime = await _services.profileRuntimeFuture;
    final nextMode = switch (activation) {
      'true' => 'always',
      'false' => 'manual',
      'toggle-active' => runtime.isActive(profileId) ? 'manual' : 'always',
      _ => 'toggle',
    };
    final updated = ShowRunnerProfile(
      name: profile.name,
      activationMode: nextMode,
      triggers: profile.triggers,
      activationCondition: profile.activationCondition,
      activationAutomation: profile.activationAutomation,
      deactivationAutomation: profile.deactivationAutomation,
      extra: profile.extra,
    );
    if (updated.activationMode != profile.activationMode) {
      await repository.save(updated);
    }
    final desired = runtime.shouldBeActive(updated, context: context);
    await runtime.setManagedActive(
      profileId,
      updated,
      active: desired,
      context: context,
    );
    return runtime.isActive(profileId);
  }

  Future<void> _persistNavigation() async {
    if (!_restoredNavigation) return;
    _navigationWrite = _navigationWrite.then((_) async {
      final settings = await widget.dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      await widget.dataService.savePluginSettings('showrunner-flutter', {
        ...settings,
        ..._workspaceDocuments.toSettings(),
        ..._automationDocuments.toSettings(),
        'selectedResourceType': ?_selectedResourceType,
        'selectedResourceId': ?_selectedResourceId,
      });
    });
    await _navigationWrite;
  }
}
