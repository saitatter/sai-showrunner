part of '../main.dart';

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
    final automation = AutomationData(
      extra: const {'name': 'Packaged automation smoke'},
      graph: AutomationGraph(
        nodes: [
          GraphNode(
            id: 'convert',
            type: 'action',
            x: 80,
            y: 80,
            data: {
              'plugin': 'ShowRunner',
              'action': 'convertNumberToString',
              'config': {'value': 42},
              'resultMapping': {'value': 'smokeValue'},
            },
          ),
        ],
        entryNodeId: 'convert',
      ),
    );
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
    final editor = ShowRunnerGraphEditor(registry: registry);
    ShowRunnerGraphEditor? reopenedEditor;
    try {
      final conditionId = editor.addNodeType('if');
      final actionId = editor.addNodeType('overlays.triggerWidget');
      if (conditionId == null || actionId == null) {
        throw StateError('Workflow smoke could not create its graph nodes.');
      }
      editor.updateNodeConfig(actionId, const {
        'widgetId': 'workflow-widget',
        'overlayId': 'workflow-overlay',
        'payload': {'source': 'packaged-workflow'},
      });
      final link = editor.controller.addLink(
        conditionId,
        'then',
        actionId,
        'exec',
        eventId: 'workflow-condition-action',
      );
      if (link == null) {
        throw StateError('Workflow smoke could not connect its control flow.');
      }

      final created = editor.toAutomation(
        const AutomationData(extra: {'name': 'Packaged workflow smoke'}),
      );
      final file = File(
        '${widget.dataService.userDirectory.path}/automations/workflow.yaml',
      );
      final repository = AutomationRepository(file);
      await repository.save(created);
      final loaded = await repository.load();
      if (loaded == null) {
        throw StateError('Workflow smoke could not reopen its saved graph.');
      }
      final nodesByType = {
        for (final node in loaded.graph.nodes) node.type: node,
      };
      final flowEdge = loaded.graph.edges
          .where(
            (edge) =>
                edge.from == nodesByType['if']?.id &&
                edge.to == nodesByType['action']?.id,
          )
          .firstOrNull;
      if (loaded.graph.entryNodeId != nodesByType['if']?.id ||
          nodesByType['if'] == null ||
          nodesByType['action'] == null ||
          flowEdge?.port != 'then') {
        throw StateError(
          'Workflow smoke did not persist the editor control-flow graph.',
        );
      }

      reopenedEditor = ShowRunnerGraphEditor(registry: registry)
        ..loadAutomation(loaded);
      if (reopenedEditor.controller.nodes.length != 2) {
        throw StateError('Workflow smoke did not restore both graph nodes.');
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
    final activation = AutomationData(
      graph: AutomationGraph(
        nodes: [
          GraphNode(
            id: 'activate',
            type: 'action',
            x: 80,
            y: 80,
            data: {
              'plugin': 'ShowRunner',
              'action': 'convertBooleanToString',
              'config': {'value': true},
              'resultMapping': {'value': 'profileValue'},
            },
          ),
        ],
        entryNodeId: 'activate',
      ),
    );
    final profile = ShowRunnerProfile(
      name: 'Packaged profile smoke',
      activationMode: 'manual',
      triggers: const [],
      activationCondition: const {},
      activationAutomation: activation,
      deactivationAutomation: const AutomationData(),
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
