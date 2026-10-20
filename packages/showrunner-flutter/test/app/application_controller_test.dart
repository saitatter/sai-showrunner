import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/application_controller.dart';
import 'package:showrunner_flutter/app/workspace_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'application owner restores, flushes navigation and awaits repeatable shutdown',
    () async {
      final root = await Directory.systemTemp.createTemp('application-owner-');
      final data = ShowRunnerDataService(root);
      await data.savePluginSettings('showrunner-flutter', {
        'disabledPlugins': ['obs', 'aitum', 'advss', 'input'],
      });
      final app = ApplicationController.create(
        dataService: data,
        smokeMode: true,
        loadSampleGraph: false,
      );
      await Future.wait([app.start(), app.start()]);
      app.navigation.openWorkspace(WorkspaceIds.chat);
      final saved = app.navigation.persist();
      await Future.wait([app.shutdown(), app.shutdown()]);
      await saved;
      expect(
        (await data.loadPluginSettings(
          'showrunner-flutter',
        ))['selectedWorkspace'],
        'workspace.chat',
      );
      await expectLater(app.start(), throwsStateError);
      await root.delete(recursive: true);
    },
  );
}
