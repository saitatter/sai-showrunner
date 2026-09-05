import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';

void main() {
  test('writes the Flutter plugin contract snapshot', () async {
    final registry = createDefaultPluginRegistry();
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
              'resources': const <String>[],
              'ui': {
                'workspaceBuilder': plugin.workspaceBuilder != null,
              },
            },
        ],
      };
      final output = Platform.environment['SHOWRUNNER_PARITY_OUTPUT'];
      if (output == null || output.isEmpty) {
        fail('SHOWRUNNER_PARITY_OUTPUT was not provided.');
      }
      await File(output).writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot),
      );
    } finally {
      await registry.close();
    }
  });
}
