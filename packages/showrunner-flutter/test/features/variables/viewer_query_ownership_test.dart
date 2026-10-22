import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/variables/variables_workspace.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

void main() {
  testWidgets('a delayed viewer query cannot replace a newer sort result', (
    tester,
  ) async {
    final repository = _Queries();
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
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Refresh'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
    await tester.pump();
    await tester.tap(find.byTooltip('Descending'));
    await tester.pump();
    ViewerDataRow row(String id) => ViewerDataRow(
      provider: 'twitch',
      viewer: ViewerIdentity(id: id, displayName: id),
      values: {},
    );
    repository.second.complete([row('new')]);
    await tester.pumpAndSettle();
    expect(find.text('new (new)'), findsOneWidget);
    repository.first.complete([row('old')]);
    await tester.pumpAndSettle();
    expect(find.text('new (new)'), findsOneWidget);
    expect(find.text('old (old)'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Queries implements ViewerDataRepository {
  final first = Completer<List<ViewerDataRow>>(),
      second = Completer<List<ViewerDataRow>>();
  int calls = 0;
  @override
  Future<List<ViewerVariableDefinition>> loadDefinitions() async => [];
  @override
  Future<List<ViewerDataRow>> queryViewers(
    String provider, {
    int start = 0,
    int? end,
    String sortBy = 'id',
    bool descending = false,
  }) => ++calls == 1 ? first.future : second.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
