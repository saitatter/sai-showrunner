part of 'showrunner_page.dart';

extension _ShowRunnerSmokeScenarios on _ShowRunnerPageState {
  Future<void> _runSmokeScenario() async {
    try {
      await Future.wait([
        _healthFuture,
        _pluginRegistryFuture,
        _profileRuntimeFuture,
      ]);
      final scenario = widget.smokeScenario;
      if (scenario == 'first-run') {
        final appSettings = await widget.dataService.loadPluginSettings(
          'showrunner-flutter',
        );
        final providerSettings = await Future.wait([
          widget.dataService.loadPluginSettings('obs'),
          loadTwitchChannelSettings(widget.dataService),
          widget.dataService.loadPluginSettings('youtube'),
        ]);
        if (appSettings['setupCompleted'] == true ||
            providerSettings.any((settings) => settings.isNotEmpty)) {
          throw StateError('First-run smoke started with existing setup data.');
        }
      } else if (scenario == 'automation') {
        await _runAutomationSmoke();
      } else if (scenario == 'workflow') {
        await _runWorkflowSmoke();
      } else if (scenario == 'profile') {
        await _runProfileSmoke();
      } else if (scenario == 'integrations') {
        await _runIntegrationsSmoke();
      } else if (scenario == 'overlays') {
        await _runOverlaySmoke();
      } else if (scenario == 'updates') {
        await _runUpdateSmoke();
      } else if (scenario != 'startup') {
        throw ArgumentError.value(
          scenario,
          'smokeScenario',
          'Expected startup, first-run, automation, workflow, profile, '
              'integrations, overlays, or updates.',
        );
      }
      stdout.writeln('Flutter smoke passed: $scenario');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // Smoke runs are already isolated and must not open the interactive
      // hide-to-tray/close dialog introduced for normal desktop shutdown.
      if (Platform.isWindows) await _handleWindowClose(forceClose: true);
    } catch (error, stackTrace) {
      stderr.writeln('Flutter smoke failed: $error');
      stderr.writeln(stackTrace);
      exitCode = 1;
      if (Platform.isWindows) await windowManager.destroy();
    }
  }

  Future<void> _runAutomationSmoke() async {
    final automation = _smokeActionDocument(
      'convert',
      'convertNumberToString',
      {'value': 42},
      'smokeValue',
    ).withMetadata({'name': 'Packaged automation smoke'});
    final file = File(
      '${widget.dataService.userDirectory.path}/automations/smoke.yaml',
    );
    final repository = AutomationRepository(file);
    await repository.save(automation);
    final loaded = await repository.load();
    if (loaded == null) {
      throw StateError('Automation smoke could not reload its fixture.');
    }
    final registry = await _pluginRegistryFuture;
    final result = await _graphExecutionEngine.executeWithRegistry(
      automation: loaded,
      context: EvaluationContext(),
      registry: registry,
    );
    if (!result.completed || result.contextState['smokeValue'] != '42') {
      throw StateError(
        'Automation smoke did not execute and map the action result.',
      );
    }
  }

  Future<void> _runWorkflowSmoke() async {
    final registry = await _pluginRegistryFuture;
    final editor = AutomationEditorController(
      document: AutomationDocument.empty(),
      registry: registry,
    );
    AutomationEditorController? reopenedEditor;
    try {
      final conditionId = editor.addNode(
        'showrunner.if',
        const GraphPoint(40, 80),
      );
      final actionId = editor.addNode(
        actionNodeType('overlays', 'triggerWidget'),
        const GraphPoint(400, 80),
      );
      editor.graph.execute(
        UpdateNodeDataCommand(mainAutomationSpace, actionId, {
          'config': {
            'widgetId': 'workflow-widget',
            'overlayId': 'workflow-overlay',
            'payload': {'source': 'packaged-workflow'},
          },
        }),
      );
      editor.graph.execute(
        AddConnectionCommand(
          mainAutomationSpace,
          GraphConnection(
            id: 'workflow-condition-action',
            from: PortRef(nodeId: conditionId, portId: 'flow:then'),
            to: PortRef(nodeId: actionId, portId: 'exec.in'),
            kind: GraphConnectionKind.control,
          ),
        ),
      );
      final created = editor.document.withMetadata({
        'name': 'Packaged workflow smoke',
      });
      final file = File(
        '${widget.dataService.userDirectory.path}/automations/workflow.yaml',
      );
      final repository = AutomationRepository(file);
      await repository.save(created);
      final loaded = await repository.load();
      if (loaded == null) {
        throw StateError('Workflow smoke could not reopen its saved graph.');
      }
      final space = loaded.graph.spaces[mainAutomationSpace]!;
      final flowEdge = space.connections['workflow-condition-action'];
      if (loaded.entryNodeId != conditionId ||
          space.nodes.length != 2 ||
          flowEdge?.from.portId != 'flow:then') {
        throw StateError(
          'Workflow smoke did not persist the canonical control-flow graph.',
        );
      }
      reopenedEditor = AutomationEditorController(
        document: loaded,
        registry: registry,
      );
      if (reopenedEditor.graph.activeSpace!.nodes.length != 2) {
        throw StateError('Workflow smoke lost nodes.');
      }
      final result = await _graphExecutionEngine.executeWithRegistry(
        automation: loaded,
        context: EvaluationContext(),
        registry: registry,
      );
      if (!result.completed) {
        throw StateError(
          'Workflow smoke did not test-run the saved control-flow graph.',
        );
      }
    } finally {
      reopenedEditor?.dispose();
      editor.dispose();
    }
  }

  Future<void> _runProfileSmoke() async {
    final activation = _smokeActionDocument(
      'activate',
      'convertBooleanToString',
      {'value': true},
      'profileValue',
    );
    final profile = ShowRunnerProfile(
      name: 'Packaged profile smoke',
      activationMode: 'manual',
      triggers: const [],
      activationCondition: const {},
      activationAutomation: activation,
      deactivationAutomation: AutomationDocument.empty(),
    );
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/smoke.yaml',
    );
    final repository = ProfileRepository(file);
    await repository.save(profile);
    final loaded = await repository.load();
    if (loaded == null) {
      throw StateError('Profile smoke could not reload its fixture.');
    }
    final runtime = await _profileRuntimeFuture;
    final result = await runtime.activate('smoke', loaded);
    if (!runtime.isActive('smoke') ||
        !result.completed ||
        result.contextState['profileValue'] != 'true') {
      throw StateError('Profile smoke did not activate its automation.');
    }
    await runtime.deactivate('smoke', loaded);
    if (runtime.isActive('smoke')) {
      throw StateError('Profile smoke did not deactivate cleanly.');
    }
  }

  Future<void> _runIntegrationsSmoke() async {
    final registry = await _pluginRegistryFuture;
    const requiredPlugins = [
      'ShowRunner',
      'obs',
      'twitch',
      'youtube',
      'overlays',
      'input',
      'remote',
    ];
    final missing = requiredPlugins
        .where((pluginId) => registry.findPlugin(pluginId) == null)
        .toList();
    if (missing.isNotEmpty) {
      throw StateError('Integration smoke is missing: ${missing.join(', ')}.');
    }
    if (registry.plugins.length < requiredPlugins.length) {
      throw StateError(
        'Integration smoke loaded an incomplete plugin catalog.',
      );
    }
  }

  Future<void> _runOverlaySmoke() async {
    final registry = await _pluginRegistryFuture;
    final event = _eventHub.stream(OverlayEventIds.widget).first;
    final result = await registry.invokeActionKey(
      const ActionKey(
        plugin: PluginId('overlays'),
        action: ActionId('triggerWidget'),
      ),
      {
        'widgetId': 'smoke-widget',
        'overlayId': 'smoke-overlay',
        'payload': {'source': 'packaged-smoke'},
      },
    );
    final payload = await event.timeout(const Duration(seconds: 1));
    if (result is! Map ||
        result['triggered'] != true ||
        payload['widgetId'] != 'smoke-widget' ||
        payload['overlayId'] != 'smoke-overlay') {
      throw StateError('Overlay smoke did not publish the widget event.');
    }
  }

  Future<void> _runUpdateSmoke() async {
    final current = await UpdateCheckService(
      currentVersion: showRunnerFlutterVersion,
      fetcher: () async => {'tag_name': 'v$showRunnerFlutterVersion'},
    ).check();
    final available = await UpdateCheckService(
      currentVersion: showRunnerFlutterVersion,
      fetcher: () async => {
        'tag_name': 'v2.0.1',
        'body': 'Smoke update',
        'html_url': 'https://example.test/releases/v2.0.1',
      },
    ).check();
    if (current.status != UpdateStatus.upToDate ||
        current.hasUpdate ||
        available.status != UpdateStatus.available ||
        !available.hasUpdate) {
      throw StateError('Update smoke did not classify release states.');
    }
  }
}

AutomationDocument _smokeActionDocument(
  String id,
  String action,
  JsonMap config,
  String target,
) {
  final document = AutomationDocument.empty();
  return AutomationDocument(
    graph: document.graph.copyWith(
      spaces: {
        mainAutomationSpace: GraphSpace(
          id: mainAutomationSpace,
          nodes: {
            id: GraphNode(
              id: id,
              type: actionNodeType('ShowRunner', action),
              data: {
                'config': config,
                'resultMapping': {'value': target},
              },
            ),
          },
          nodePresentations: {
            id: NodePresentation(
              nodeId: id,
              position: const GraphPoint(80, 80),
            ),
          },
        ),
      },
    ),
    settings: {'entryNodeId': id},
  );
}
