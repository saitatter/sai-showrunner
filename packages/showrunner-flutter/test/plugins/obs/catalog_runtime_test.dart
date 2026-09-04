import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/obs/catalog_runtime.dart';
import 'package:showrunner_flutter/plugins/obs/ui/obs_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'loads OBS scenes and source transforms through an injectable call',
    () async {
      final directory = await Directory.systemTemp.createTemp('obs-catalog-');
      addTearDown(() => directory.delete(recursive: true));
      final requests = <String>[];
      final catalog = await ObsCatalogService(
        dataService: ShowRunnerDataService(directory),
        call: (request, data) async {
          requests.add(request);
          return switch (request) {
            'GetSceneList' => {
              'currentProgramSceneName': 'Main',
              'scenes': [
                {'sceneName': 'Main'},
                {'sceneName': 'BRB'},
              ],
            },
            'GetSceneItemList' when data['sceneName'] == 'Main' => {
              'sceneItems': [
                {
                  'sceneItemId': 7,
                  'sourceName': 'Camera',
                  'sceneItemEnabled': true,
                  'sceneItemTransform': {
                    'positionX': 10,
                    'positionY': 20,
                    'scaleX': 1,
                    'scaleY': 1,
                  },
                },
              ],
            },
            'GetInputList' => {
              'inputs': [
                {'inputName': 'Camera', 'inputKind': 'dshow_input'},
              ],
            },
            'GetSourceFilterList' => {
              'filters': [
                {'filterName': 'Color Correction', 'filterEnabled': false},
              ],
            },
            _ => {'sceneItems': []},
          };
        },
      ).load();

      expect(requests, [
        'GetSceneList',
        'GetSceneItemList',
        'GetSceneItemList',
        'GetInputList',
        'GetSourceFilterList',
      ]);
      expect(catalog.scenes, ['Main', 'BRB']);
      expect(catalog.currentProgramScene, 'Main');
      expect(catalog.itemsByScene['Main']!.single.sourceName, 'Camera');
      expect(catalog.itemsByScene['Main']!.single.transform['positionX'], 10);
      expect(catalog.inputKindsByName['Camera'], 'dshow_input');
      expect(
        catalog.filtersBySource['Camera']!.single.name,
        'Color Correction',
      );
      expect(catalog.filtersBySource['Camera']!.single.enabled, isFalse);
    },
  );

  testWidgets('loads the OBS catalog when the workspace opens', (tester) async {
    final dataService = ShowRunnerDataService(
      Directory('test-obs-widget-user-do-not-create'),
    );
    final catalogService = ObsCatalogService(
      dataService: dataService,
      call: (request, data) async => switch (request) {
        'GetSceneList' => {
          'currentProgramSceneName': 'Main',
          'scenes': [
            {'sceneName': 'Main'},
          ],
        },
        'GetSceneItemList' => {
          'sceneItems': [
            {
              'sceneItemId': 7,
              'sourceName': 'Camera',
              'sceneItemTransform': {'positionX': 10},
            },
          ],
        },
        'GetInputList' => {
          'inputs': [
            {'inputName': 'Camera', 'inputKind': 'dshow_input'},
          ],
        },
        'GetSourceFilterList' => {
          'filters': [
            {'filterName': 'Color Correction', 'filterEnabled': true},
          ],
        },
        _ => {},
      },
    );
    final registry = DartPluginRegistry()
      ..register(
        createObsPlugin(CallbackObsTransport((request, data) async => {})),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: ObsWorkspace(
          dataService: dataService,
          registryFuture: Future.value(registry),
          catalogService: catalogService,
          settingsFuture: Future.value(<String, dynamic>{}),
        ),
      ),
    );
    for (var index = 0; index < 10; index++) {
      await tester.pump();
    }
    await tester.scrollUntilVisible(
      find.text('Scenes and sources'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Scenes and sources'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
  });
}
