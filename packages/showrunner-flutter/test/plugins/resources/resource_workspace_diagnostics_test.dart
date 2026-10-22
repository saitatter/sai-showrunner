import 'dart:io';
import 'package:showrunner_flutter/schema/identifiers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/resources_workspace.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('a resource dialog cannot create in a replacement project', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('resource-owner-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final first = ShowRunnerDataService(Directory('${root.path}/first'));
    final second = ShowRunnerDataService(Directory('${root.path}/second'));
    final editors = createDefaultResourceEditorRegistry();
    Future<void> show(ShowRunnerDataService data) async {
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ResourcesWorkspace(
                dataService: data,
                editorRegistry: editors,
                resourceType: 'Variable',
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
    }

    await show(first);
    await tester.tap(find.text('New resource'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Old project draft');
    await show(second);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(
        await first.storage.resource(const ResourceTypeId('Variable')).list(),
        isEmpty,
      );
      expect(
        await second.storage.resource(const ResourceTypeId('Variable')).list(),
        isEmpty,
      );
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
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
