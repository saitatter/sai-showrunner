import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_schema.dart';
import 'package:showrunner_flutter/graph/ui/automation_graph_schema_input.dart';
import 'package:showrunner_flutter/schema/identifiers.dart';

void main() {
  const schema = DartDataInputSchema(
    label: 'Connection',
    kind: DartDataInputKind.resource,
    resourceType: ResourceTypeId('OBSConnection'),
  );
  Widget app(ResourceOptionsLoader loader, {Object? value}) => MaterialApp(
    home: Scaffold(
      body: AutomationGraphSchemaInput(
        schema: schema,
        value: value,
        loader: loader,
        onChanged: (_) {},
      ),
    ),
  );
  testWidgets(
    'resource options retry without exposing errors or rereading on builds',
    (tester) async {
      var calls = 0;
      final first = Completer<List<String>>();
      final retry = Completer<List<String>>();
      Future<List<String>> loader(String _) {
        calls++;
        return calls == 1 ? first.future : retry.future;
      }

      await tester.pumpWidget(app(loader));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      first.completeError(StateError('private-provider-marker'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private-provider-marker'), findsNothing);
      expect(find.textContaining('Unable to load Connection'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      expect(calls, 2);
      retry.complete(['portable']);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DartDataInput>(find.byType(DartDataInput)).schema.options,
        ['portable'],
      );
      await tester.pumpWidget(app(loader, value: 'portable'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('a replaced resource loader cannot publish late options', (
    tester,
  ) async {
    final old = Completer<List<String>>();
    final current = Completer<List<String>>();
    await tester.pumpWidget(app((_) => old.future));
    await tester.pumpWidget(app((_) => current.future));
    current.complete(['current']);
    await tester.pumpAndSettle();
    old.complete(['stale']);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DartDataInput>(find.byType(DartDataInput)).schema.options,
      ['current'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
