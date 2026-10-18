import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import '../support/graph_fixtures.dart';
import 'package:showrunner_flutter/schema/data_input.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

Map<String, dynamic> _schema(DartDataInputSchema field) => {
  'key': field.key,
  'label': field.label,
  'type': field.kind.name,
  if (field.required) 'required': true,
  if (field.secret) 'secret': true,
  if (field.resourceType != null) 'resourceType': field.resourceType!.value,
  if (field.options.isNotEmpty) 'options': field.options,
  if (field.fields.isNotEmpty) 'fields': field.fields.map(_schema).toList(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'every exposed action and trigger can be inserted and serialized as a graph node',
    () async {
      final hub = DartPluginEventHub();
      addTearDown(hub.dispose);
      final registry = createDefaultPluginRegistry(eventHub: hub);
      final editor = AutomationEditorController(
        document: AutomationDocument.empty(),
        registry: registry,
      );
      addTearDown(editor.dispose);
      addTearDown(registry.close);
      var actions = 0;
      var triggers = 0;
      final catalog = <Map<String, dynamic>>[];
      final yaml = StringBuffer(
        '''# Copy to connections.local.yml; this file contains no real credentials.
# Run: ./scripts/test-live-nodes.ps1 -ConfigPath <path-to-local-yml>
# Only enabled scenarios run. Settings are written to an isolated temporary profile.
version: 1
enabled_plugins: [ShowRunner, http, time, random, variables, overlays]
plugin_settings:
''',
      );
      for (final plugin in registry.plugins) {
        final id = plugin.id.value;
        if (plugin.settings.isNotEmpty) {
          yaml.writeln('  ${jsonEncode(id)}:');
          for (final setting in plugin.settings) {
            final value = setting.secret ? '' : setting.defaultValue ?? '';
            yaml.writeln(
              '    ${jsonEncode(setting.id.value)}: ${jsonEncode(value)} # ${setting.displayName}${setting.secret ? ' (SECRET)' : ''}',
            );
          }
        }
        for (final action in plugin.actions) {
          final key = actionNodeType(id, action.actionId.value);
          final nodeId = editor.addNode(key, GraphPoint(actions * 320, 0));
          expect(editor.graph.activeSpace!.nodes[nodeId]!.type, key);
          actions++;
        }
        for (final trigger in plugin.triggers) {
          final key = triggerNodeType(id, trigger.triggerId.value);
          expect(
            editor.addNode(key, GraphPoint(triggers * 320, 400)),
            isNotEmpty,
            reason: key,
          );
          triggers++;
        }
        catalog.add({
          'id': id,
          'name': plugin.name,
          'actions': [
            for (final action in plugin.actions)
              {
                'id': action.actionId.value,
                'name': action.displayName,
                'config': action.configSchema == null
                    ? null
                    : _schema(action.configSchema!),
                'result': action.resultSchema == null
                    ? null
                    : _schema(action.resultSchema!),
                'liveStatus': 'pending',
              },
          ],
          'triggers': [
            for (final trigger in plugin.triggers)
              {
                'id': trigger.triggerId.value,
                'name': trigger.displayName,
                'config': trigger.configSchema == null
                    ? null
                    : _schema(trigger.configSchema!),
                'liveStatus': 'pending',
              },
          ],
          'resources': [
            for (final resource in plugin.resources)
              {
                'type': resource.resourceTypeId.value,
                'directory': resource.storageDirectory,
                'defaultConfig': resource.createDefaultConfig('QA resource'),
              },
          ],
        });
      }
      final saved = editor.document;
      expect(
        saved.graph.spaces[mainAutomationSpace]!.nodes.values.where(
          (node) => decodeContractNodeType(node.type, 'action') != null,
        ),
        hasLength(actions),
      );
      expect(
        saved.graph.spaces[mainAutomationSpace]!.nodes.values.where(
          (node) => decodeContractNodeType(node.type, 'trigger') != null,
        ),
        hasLength(triggers),
      );
      final restored = AutomationEditorController(
        registry: registry,
        document: AutomationDocument.fromJson(saved.toJson()),
      );
      addTearDown(restored.dispose);
      expect(restored.graph.activeSpace!.nodes.length, actions + triggers);
      expect(restored.document.graph, saved.graph);
      // These checks exercise the editor/serialization contract, not external services.
      stdout.writeln(
        '${registry.plugins.length} plugins, $actions action nodes, $triggers trigger nodes round-tripped.',
      );
      if (const bool.fromEnvironment('SHOWRUNNER_EXPORT_CATALOG')) {
        final file = File('../../docs/testing/node-catalog.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 1,
            'plugins': catalog,
            'counts': {'plugins': registry.plugins.length, 'actions': actions, 'triggers': triggers},
            'note': 'Insertion and serialization passed; live execution requires enabled scenarios and connections.',
          })}\n',
        );
        yaml.write('''
# Resource references use these isolated IDs, not your production profile IDs.
resources: []
# Example OBS resource (add obs to enabled_plugins):
# - type: OBSConnection
#   id: qa-obs
#   config: {name: QA OBS, host: 127.0.0.1, port: 4455, password: ""}

scenarios:
  - name: Local number conversion
    enabled: true
    plugin: ShowRunner
    action: convertNumberToString
    config: {value: 42}
    expect: {value: "42"}
  # Add one enabled scenario for each live action you want to test.
  # The exact action IDs and configuration fields are in docs/testing/node-catalog.json.
''');
        for (final plugin in registry.plugins) {
          for (final action in plugin.actions) {
            if (plugin.id.value == 'ShowRunner' &&
                action.actionId.value == 'convertNumberToString') {
              continue;
            }
            final config = action.configSchema == null
                ? <String, dynamic>{}
                : constructDartDataInputDefault(action.configSchema!);
            yaml.writeln(
              '  - name: ${jsonEncode('${plugin.name}: ${action.displayName ?? action.actionId.value}')}',
            );
            yaml.writeln('    enabled: false');
            yaml.writeln('    plugin: ${jsonEncode(plugin.id.value)}');
            yaml.writeln('    action: ${jsonEncode(action.actionId.value)}');
            yaml.writeln('    config: ${jsonEncode(config)}');
          }
        }
        await File(
          'test/live/connections.example.yml',
        ).writeAsString(yaml.toString());
      }
    },
  );
}
