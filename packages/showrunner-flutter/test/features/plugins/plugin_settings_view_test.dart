import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/plugins/plugin_settings_snapshot.dart';
import 'package:showrunner_flutter/features/plugins/plugin_diagnostic_preview.dart';
import 'package:showrunner_flutter/schema/data_input.dart';
import 'package:showrunner_flutter/features/plugins/plugin_setting_value.dart';
import 'package:showrunner_flutter/features/plugins/plugin_workspace.dart';
import 'package:showrunner_flutter/features/settings/plugin_preferences_panel.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_module.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

DartPluginRegistry registry(String id) => DartPluginRegistry()
  ..registerModule(
    ManifestDartPluginModule(
      DartPluginManifest(
        id: PluginId(id),
        name: id,
        settings: [
          SettingSpec(
            id: const SettingId('value'),
            displayName: '$id value',
            defaultValue: 'draft',
          ),
        ],
      ),
    ),
  );
void main() {
  test(
    'snapshot reads only declared settings and keeps unknown values and revisions',
    () async {
      final plugins = registry('sample')
        ..registerModule(
          const ManifestDartPluginModule(
            DartPluginManifest(id: PluginId('empty'), name: 'Empty'),
          ),
        );
      addTearDown(plugins.close);
      final reads = <String>[];
      final snapshot = await loadPluginSettingsSnapshot(
        registryFuture: Future.value(plugins),
        read: (id) async {
          reads.add(id);
          return {'unknown': 42};
        },
      );
      expect(reads, ['sample']);
      expect(snapshot.values['sample']!['unknown'], 42);
      expect(snapshot.revisions.containsKey('sample'), isTrue);
      expect(
        () => snapshot.values['sample']!['unknown'] = 0,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'numeric settings reject malformed and nonfinite values instead of using defaults',
    () {
      const setting = SettingSpec(
        id: SettingId('number'),
        displayName: 'Number',
        defaultValue: 5,
      );
      expect(decodePluginSettingValue(setting, '12'), 12);
      expect(
        () => decodePluginSettingValue(setting, 'invalid'),
        throwsFormatException,
      );
      const floating = SettingSpec(
        id: SettingId('floating'),
        displayName: 'Floating',
        defaultValue: 1.0,
      );
      expect(
        () => decodePluginSettingValue(floating, 'NaN'),
        throwsFormatException,
      );
    },
  );
  test(
    'usage previews retain safe fields and redact declared, unknown and URL credentials',
    () {
      const schema = DartDataInputSchema(
        label: 'Config',
        kind: DartDataInputKind.object,
        fields: [
          DartDataInputSchema(
            key: 'label',
            label: 'Label',
            kind: DartDataInputKind.text,
          ),
          DartDataInputSchema(
            key: 'private',
            label: 'Private',
            kind: DartDataInputKind.text,
            secret: true,
          ),
          DartDataInputSchema(
            key: 'url',
            label: 'URL',
            kind: DartDataInputKind.text,
          ),
          DartDataInputSchema(
            key: 'headers',
            label: 'Headers',
            kind: DartDataInputKind.object,
          ),
        ],
      );
      final config = <String, dynamic>{
        'label': 'visible',
        'private': 'private-marker',
        'unknown': 'unknown-marker',
        'url':
            'https://user:password-marker@example.test/path?access_token=query-marker',
        'headers': {'Authorization': 'Bearer header-marker'},
      };
      final preview = safePluginConfigPreview(config, [schema]);
      expect(preview, contains('visible'));
      for (final marker in [
        'private-marker',
        'unknown-marker',
        'password-marker',
        'query-marker',
        'header-marker',
      ]) {
        expect(preview, isNot(contains(marker)));
      }
      expect(config['private'], 'private-marker');
      expect(
        safePluginConfigPreview({'value': 'unavailable-marker'}, []),
        isNot(contains('unavailable-marker')),
      );
    },
  );
  for (final preferences in [false, true]) {
    testWidgets(
      'replaced ${preferences ? 'preferences' : 'plugin'} loader cannot publish another form',
      (tester) async {
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('plugin-settings-view-'),
        ))!;
        final data = ShowRunnerDataService(root), hub = DartPluginEventHub();
        final events = ProviderEventRuntime(dataService: data, eventHub: hub);
        final old = registry('old'), current = registry('current');
        final pending = Completer<DartPluginRegistry>();
        addTearDown(
          () => tester.runAsync(() async {
            await events.stop();
            events.dispose();
            await hub.dispose();
            await old.close();
            await current.close();
            await root.delete(recursive: true);
          }),
        );
        Widget app(Future<DartPluginRegistry> future, String id) => MaterialApp(
          home: Scaffold(
            body: preferences
                ? SingleChildScrollView(
                    child: PluginPreferencesPanel(
                      dataService: data,
                      registryFuture: future,
                      filter: '',
                    ),
                  )
                : PluginWorkspace(
                    dataService: data,
                    registryFuture: future,
                    providerEvents: events,
                    selectedPluginId: id,
                    forceGenericDetails: true,
                  ),
          ),
        );
        await tester.pumpWidget(app(pending.future, 'old'));
        await tester.pumpWidget(app(Future.value(current), 'current'));
        pending.complete(old);
        for (var i = 0; i < 200; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
        if (!preferences) {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Settings 1'));
          await tester.pump();
        }
        expect(find.widgetWithText(TextField, 'current value'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'old value'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
