import 'package:showrunner_flutter/features/resources/resource_editor_availability.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_form.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  testWidgets(
    'disabling an owner blocks focus but retains the mounted editor draft',
    (tester) async {
      final registry = DartPluginRegistry()..register(createOverlaysPlugin());
      addTearDown(registry.close);
      final contribution = createDefaultResourceEditorRegistry().find(
        'Overlay',
      )!;
      final registryFuture = Future.value(registry);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResourceEditorAvailability(
              contribution: contribution,
              resource: const ResourceData(id: 'one', config: {}),
              registryFuture: registryFuture,
              builder: (_) => const TextField(key: Key('retained-input')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('retained-input')),
        'Unsaved draft',
      );
      final originalState = tester.state(find.byType(EditableText));
      registry.setPluginEnabledId(contribution.ownerId, false);
      await tester.pumpAndSettle();
      expect(find.textContaining('owning plugin is disabled'), findsOneWidget);
      expect(find.byKey(const Key('retained-input')), findsNothing);
      registry.setPluginEnabledId(contribution.ownerId, true);
      await tester.pumpAndSettle();
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(tester.state(find.byType(EditableText)), same(originalState));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final type in ['Overlay', 'Dashboard', 'StreamPlan']) {
    testWidgets('$type malformed collections are read-only and cannot save', (
      tester,
    ) async {
      final registry = createDefaultResourceEditorRegistry();
      final key = {
        'Overlay': 'widgets',
        'Dashboard': 'pages',
        'StreamPlan': 'segments',
      }[type]!;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => registry.build(
              ResourceTypeId(type),
              context,
              ResourceData(
                id: 'broken',
                config: {
                  key: ['malformed'],
                  'password': 'private-marker',
                },
              ),
              (_) async {
                saves++;
              },
            ),
          ),
        ),
      );
      expect(find.text('Resource cannot be edited'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(find.textContaining('private-marker'), findsNothing);
      expect(saves, 0);
    });
  }

  for (final type in ['UnknownType', 'Overlay']) {
    testWidgets(
      '$type unavailable contributions expose safe read-only metadata',
      (tester) async {
        final registry = createDefaultResourceEditorRegistry();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => registry.build(
                ResourceTypeId(type),
                context,
                const ResourceData(
                  id: 'unavailable',
                  config: {'accessToken': 'private-marker'},
                ),
                (_) async => fail('read-only resource attempted a save'),
                enabled: false,
              ),
            ),
          ),
        );
        expect(find.text('Resource cannot be edited'), findsOneWidget);
        expect(find.textContaining('private-marker'), findsNothing);
      },
    );
  }

  testWidgets(
    'save conflicts keep the draft open and omit arbitrary error content',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ResourceForm(
                  title: 'Draft',
                  fields: const [Text('Unsaved content')],
                  onSave: () async =>
                      throw PersistenceConflictException('private-marker'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved content'), findsOneWidget);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(find.textContaining('private-marker'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a pending save rejects duplicate submission and closes after acceptance',
    (tester) async {
      final accepted = Completer<void>();
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ResourceForm(
                  title: 'Draft',
                  fields: const [Text('Unsaved content')],
                  onSave: () {
                    saves++;
                    return accepted.future;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saves, 1);
      expect(find.text('Unsaved content'), findsOneWidget);
      accepted.complete();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved content'), findsNothing);
    },
  );
}
