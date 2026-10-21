import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/resources_workspace.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'corrupt resources stay visible without opening a writable editor or echoing source',
    (tester) async {
      final root = (await tester.runAsync(
        () =>
            Directory.systemTemp.createTemp('showrunner-resource-diagnostics-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      await tester.runAsync(() async {
        final directory = await Directory('${root.path}/overlays').create();
        await File(
          '${directory.path}/broken.json',
        ).writeAsString('{ private-marker');
      });
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ResourcesWorkspace(
                dataService: ShowRunnerDataService(root),
                editorRegistry: createDefaultResourceEditorRegistry(),
                resourceType: 'Overlay',
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Overlay / broken.json').evaluate().isNotEmpty) break;
      }
      expect(find.text('Overlay / broken.json'), findsOneWidget);
      expect(find.textContaining('malformed'), findsOneWidget);
      expect(find.textContaining('private-marker'), findsNothing);
      expect(find.text('Save'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        expect(
          await File('${root.path}/overlays/broken.json').readAsString(),
          '{ private-marker',
        );
      });
    },
  );
}
