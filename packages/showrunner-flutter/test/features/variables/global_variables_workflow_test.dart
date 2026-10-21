import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/variables/variables_workspace.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/variables/runtime.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('session variable reset, edit, search, restart and deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('showrunner-variable-ui-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final repository = ResourceRepository(Directory('${root.path}/variables'));
    await tester.runAsync(
      () => repository.save(
        const ResourceData(
          id: 'counter',
          config: {
            'name': 'Session counter',
            'type': 'number',
            'defaultValue': 10,
            'persistent': false,
          },
        ),
      ),
    );
    final runtime = DartVariableRuntime(directory: repository.directory);
    addTearDown(runtime.dispose);
    await tester.runAsync(() async {
      await runtime.load();
      await runtime.setValue('counter', 25);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VariablesWorkspace(
            dataService: ShowRunnerDataService(root),
            variableRuntime: runtime,
          ),
        ),
      ),
    );
    await _until(tester, find.text('Session counter'));
    await tester.runAsync(() => tester.tap(find.byTooltip('Reset to default')));
    await _settleIo(tester, () => runtime.valueOf('counter') == 10);
    expect(runtime.valueOf('counter'), 10);
    await tester.tap(find.byTooltip('Edit variable'));
    await tester.pumpAndSettle();
    final current = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Current value',
      ),
    );
    await tester.enterText(current, '60');
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Save')),
    );
    await _settleIo(tester, () => runtime.valueOf('counter') == 60);
    expect(runtime.valueOf('counter'), 60);
    final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Search variables',
    );
    await tester.enterText(search, 'does not exist');
    await tester.pumpAndSettle();
    expect(find.text('No variables found'), findsOneWidget);
    await tester.enterText(search, 'Session');
    await tester.pumpAndSettle();
    expect(find.text('Session counter'), findsOneWidget);
    final restarted = DartVariableRuntime(directory: repository.directory);
    addTearDown(restarted.dispose);
    await tester.runAsync(restarted.load);
    expect(restarted.valueOf('counter'), 10);
    await tester.tap(find.byTooltip('Delete variable'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
    );
    await _settleIo(tester, () => runtime.definitionOf('counter') == null);
    expect(runtime.definitionOf('counter'), isNull);
    expect(await tester.runAsync(repository.list), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.close);
    await tester.runAsync(repository.list);
    await tester.pumpAndSettle();
  });
}

Future<void> _until(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (target.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Missing $target');
}

Future<void> _settleIo(WidgetTester tester, bool Function() completed) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (completed()) return;
  }
  throw TestFailure('Variable operation did not complete.');
}
