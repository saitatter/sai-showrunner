import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/variables/variables_workspace.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  testWidgets('a late save never replaces a newly selected viewer', (
    tester,
  ) async {
    final repository = _DelayedViewerRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ViewerDataWorkspacePanel(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field('Twitch viewer ID'), 'first');
    await tester.tap(find.text('Load viewer'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('points'), '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(_field('Twitch viewer ID'), 'second');
    await tester.tap(find.text('Load viewer'));
    await tester.pumpAndSettle();
    expect(find.text('Values for second'), findsOneWidget);
    repository.saved.complete(
      await repository.base.setViewerValue(
        'twitch',
        const ViewerIdentity(id: 'first', displayName: 'first'),
        'points',
        25,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Values for second'), findsOneWidget);
    expect(tester.widget<TextField>(_field('points')).controller!.text, '10');
  });

  testWidgets('a late viewer load cannot overwrite a newer selection', (
    tester,
  ) async {
    // Native integration bindings use the real platform text input by default.
    // Register the test input so both simulated submissions address the current
    // client after the first submission has unfocused the field.
    if (!tester.testTextInput.isRegistered) {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
    }
    final repository = _DelayedViewerRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ViewerDataWorkspacePanel(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field('Twitch viewer ID'), 'slow');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(_field('Twitch viewer ID'), 'second');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // A delayed load deliberately leaves a spinner active; do not wait for
    // all animations before resolving the controlled repository future.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    repository.loaded.complete(
      await repository.base.loadViewer(
        'twitch',
        const ViewerIdentity(id: 'slow', displayName: 'slow'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Values for second'), findsOneWidget);
  });
  testWidgets(
    'deleting the active sort definition keeps the viewer table usable',
    (tester) async {
      final repository = InMemoryViewerDataRepository(
        definitions: [
          const ViewerVariableDefinition(
            name: 'points',
            type: 'number',
            defaultValue: 10,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ViewerDataWorkspacePanel(repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('points').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Delete definition'));
      await tester.tap(find.byTooltip('Delete definition'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'id',
      );
    },
  );
  testWidgets('new viewers do not replace the viewer being edited', (
    tester,
  ) async {
    final hub = DartPluginEventHub();
    addTearDown(hub.dispose);
    final repository = InMemoryViewerDataRepository(
      definitions: [
        const ViewerVariableDefinition(
          name: 'points',
          type: 'number',
          defaultValue: 10,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ViewerDataWorkspacePanel(
              repository: repository,
              eventHub: hub,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field('Twitch viewer ID'), 'selected-viewer');
    await tester.tap(find.text('Load viewer'));
    await tester.pumpAndSettle();
    hub.emit('viewerDataAdded', {
      'provider': 'twitch',
      'id': 'someone-else',
      'displayName': 'Someone else',
      'values': {'points': 0},
    });
    await tester.pumpAndSettle();
    expect(find.text('Values for selected-viewer'), findsOneWidget);
    await tester.enterText(_field('points'), '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final selected = await repository.loadViewer(
      'twitch',
      const ViewerIdentity(
        id: 'selected-viewer',
        displayName: 'selected-viewer',
      ),
    );
    final other = await repository.loadViewer(
      'twitch',
      const ViewerIdentity(id: 'someone-else', displayName: 'Someone else'),
    );
    expect(selected.values['points'], 25);
    expect(other.values['points'], 10);
  });

  testWidgets('switching viewers discards the previous unsaved field draft', (
    tester,
  ) async {
    final repository = InMemoryViewerDataRepository(
      definitions: [
        const ViewerVariableDefinition(
          name: 'points',
          type: 'number',
          defaultValue: 10,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ViewerDataWorkspacePanel(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field('Twitch viewer ID'), 'first');
    await tester.tap(find.text('Load viewer'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('points'), '999');
    await tester.enterText(_field('Twitch viewer ID'), 'second');
    await tester.tap(find.text('Load viewer'));
    await tester.pumpAndSettle();
    expect(find.text('Values for second'), findsOneWidget);
    expect(tester.widget<TextField>(_field('points')).controller!.text, '10');
  });
  testWidgets('loads and edits persisted viewer variables', (tester) async {
    final repository = InMemoryViewerDataRepository(
      definitions: [
        const ViewerVariableDefinition(
          name: 'points',
          type: 'number',
          defaultValue: 10,
        ),
        const ViewerVariableDefinition(name: 'vip', type: 'boolean'),
        const ViewerVariableDefinition(name: 'title', type: 'string'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ViewerDataWorkspacePanel(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field('Twitch viewer ID'), 'viewer-42');
    await tester.tap(find.text('Load viewer'));
    await tester.pumpAndSettle();

    expect(find.text('Values for viewer-42'), findsOneWidget);
    expect(_field('points'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);

    await tester.enterText(_field('points'), '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final row = await repository.loadViewer(
      'twitch',
      const ViewerIdentity(id: 'viewer-42', displayName: 'viewer-42'),
    );
    expect(row.values['points'], 25);
    expect(row.values['vip'], true);
  });
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

class _DelayedViewerRepository implements ViewerDataRepository {
  final base = InMemoryViewerDataRepository(
    definitions: [
      const ViewerVariableDefinition(
        name: 'points',
        type: 'number',
        defaultValue: 10,
      ),
    ],
  );
  final saved = Completer<ViewerDataRow>();
  final loaded = Completer<ViewerDataRow>();
  @override
  Future<List<ViewerVariableDefinition>> loadDefinitions() =>
      base.loadDefinitions();
  @override
  Future<ViewerDataRow> loadViewer(String provider, ViewerIdentity viewer) =>
      viewer.id == 'slow' ? loaded.future : base.loadViewer(provider, viewer);
  @override
  Future<ViewerDataRow> setViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    dynamic value,
  ) => saved.future;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
