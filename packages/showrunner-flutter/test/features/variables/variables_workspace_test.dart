import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/variables/variables_workspace.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

void main() {
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
