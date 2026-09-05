import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('writes the Flutter plugin contract snapshot', () async {
    final eventHub = DartPluginEventHub();
    final queueManager = DartAutomationQueueManager(
      defaultQueue: DartActionQueue(),
      execute: (automation, context, item) async => null,
    );
    final registry = createDefaultPluginRegistry(
      eventHub: eventHub,
      queueManager: queueManager,
    );
    final resourceEditors = createDefaultResourceEditorRegistry();
    try {
      final plugins = registry.plugins.toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      final snapshot = {
        'implementation': 'flutter',
        'plugins': [
          for (final plugin in plugins)
            {
              'id': plugin.id,
              'name': plugin.name,
              'version': plugin.version,
              'settings': [
                for (final setting in plugin.settings)
                  {
                    'id': setting.id,
                    'secret': setting.secret,
                    'hasDefault': setting.defaultValue != null,
                  },
              ],
              'actions': [
                for (final action in plugin.actions)
                  {
                    'id': action.actionId,
                    'displayName': action.displayName,
                    'hasConfigSchema': action.configSchema != null,
                    'hasResultSchema': action.resultSchema != null,
                  },
              ],
              'triggers': [
                for (final trigger in plugin.triggers)
                  {
                    'id': trigger.triggerId,
                    'displayName': trigger.displayName,
                    'hasConfigSchema': trigger.configSchema != null,
                  },
              ],
              'states': [
                for (final state in plugin.states)
                  {
                    'id': state.id,
                    'hasInitialValue': state.initialValue != null,
                  },
              ],
              'resources': [
                for (final resource in resourceEditors.definitions.where(
                  (resource) =>
                      resource.pluginId.toLowerCase() ==
                      plugin.id.toLowerCase(),
                ))
                  resource.resourceType,
              ],
              'ui': {'contribution': plugin.ui != null},
            },
        ],
      };
      final configuredOutput = Platform.environment['SHOWRUNNER_PARITY_OUTPUT'];
      final temporaryOutput =
          configuredOutput == null || configuredOutput.isEmpty
          ? File(
              '${Directory.systemTemp.path}/showrunner-contract-${DateTime.now().microsecondsSinceEpoch}.json',
            )
          : null;
      final output = temporaryOutput ?? File(configuredOutput!);
      try {
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(snapshot),
        );
      } finally {
        if (temporaryOutput != null) await temporaryOutput.delete();
      }
    } finally {
      await registry.close();
      await queueManager.dispose();
      await eventHub.dispose();
    }
  });
}
