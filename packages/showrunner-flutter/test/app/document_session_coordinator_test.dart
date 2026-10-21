import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/app/documents/document_session_coordinator.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/plugins/stream_plans/manifest.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'owned shutdown cancels a pending close prompt without waiting for UI disposal',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'document-prompt-shutdown-',
      );
      final documents = DocumentSessionCoordinator(
        dataService: ShowRunnerDataService(root),
        scratchDocument: AutomationDocument.empty(),
        streamPlans: DartStreamPlanRuntime(),
      );
      final session = documents.automations.open(
        AutomationDocument.empty(),
        'one.yaml',
        unsaved: true,
      );
      session.editor.addNode('showrunner.if', GraphPoint.zero);
      final entered = Completer<void>(),
          answer = Completer<DocumentCloseDecision>();
      final closing = documents.closeAutomation('one.yaml', (_) {
        entered.complete();
        return answer.future;
      });
      await entered.future;
      await documents.close();
      expect(await closing, false);
      answer.complete(DocumentCloseDecision.discard);
      await root.delete(recursive: true);
    },
  );
  late Directory root;
  late ShowRunnerDataService data;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('document-coordinator-');
    data = ShowRunnerDataService(root);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'disabled resource owners cannot save or delete and retain dirty drafts',
    () async {
      final documents = DocumentSessionCoordinator(
        dataService: data,
        scratchDocument: AutomationDocument.empty(),
        streamPlans: DartStreamPlanRuntime(),
        canEditResource: (_) async => false,
      );
      addTearDown(documents.dispose);
      const original = ResourceData(id: 'one', config: {'name': 'Original'});
      final repository = documents.resourceRepository('Overlay');
      await repository.save(original);
      documents.overlays.open(original);
      const draft = ResourceData(id: 'one', config: {'name': 'Draft'});
      documents.overlays.update(draft, isDirty: true);
      await expectLater(
        documents.saveResource('Overlay', draft),
        throwsStateError,
      );
      await expectLater(
        documents.deleteResource(
          original,
          'Overlay',
          (_) async => DocumentCloseDecision.discard,
        ),
        throwsStateError,
      );
      expect(documents.overlays.dirty['one'], isTrue);
      expect(documents.overlays.resources['one'], same(draft));
      expect((await repository.load('one'))!.name, 'Original');
    },
  );

  test(
    'an externally changed automation preserves the dirty editor and newer file',
    () async {
      final documents = DocumentSessionCoordinator(
        dataService: data,
        scratchDocument: AutomationDocument.empty(),
        streamPlans: DartStreamPlanRuntime(),
      );
      addTearDown(documents.dispose);
      final original = AutomationDocument.empty().withMetadata({
        'name': 'Original',
      });
      final repository = documents.automationRepository('one.yaml');
      await repository.save(original);
      final session = documents.automations.open(original, 'one.yaml');
      session.editor.addNode('showrunner.if', GraphPoint.zero);
      await repository.save(original.withMetadata({'name': 'External'}));
      await expectLater(
        documents.saveAutomation(session),
        throwsA(isA<PersistenceConflictException>()),
      );
      expect(session.dirty, isTrue);
      expect(session.editor.graph.canUndo, isTrue);
      expect((await repository.load())!.metadata['name'], 'External');
    },
  );

  test(
    'save all writes every dirty session and preserves each history',
    () async {
      final documents = DocumentSessionCoordinator(
        dataService: data,
        scratchDocument: AutomationDocument.empty(),
        streamPlans: DartStreamPlanRuntime(),
      );
      addTearDown(documents.dispose);
      final first = documents.automations.open(
        AutomationDocument.empty(),
        'one.yaml',
        unsaved: true,
      );
      first.editor.addNode('showrunner.if', GraphPoint.zero);
      final second = documents.automations.open(
        AutomationDocument.empty(),
        'two.yaml',
        unsaved: true,
      );
      second.editor.addNode('showrunner.return', GraphPoint.zero);
      const overlay = ResourceData(
        id: 'overlay',
        config: {
          'name': 'Overlay',
          'widgets': [],
          'size': {'width': 100, 'height': 100},
        },
      );
      documents.overlays.update(overlay, isDirty: true);
      await documents.saveAll();
      expect(documents.hasUnsavedChanges, false);
      expect(first.editor.graph.canUndo, true);
      expect(second.editor.graph.canUndo, true);
      expect(
        (await documents.automationRepository('one.yaml').load())!
            .graph
            .spaces[mainAutomationSpace]!
            .nodes,
        hasLength(1),
      );
      expect(
        (await documents.automationRepository('two.yaml').load())!
            .graph
            .spaces[mainAutomationSpace]!
            .nodes,
        hasLength(1),
      );
      expect(
        await documents.resourceRepository('Overlay').load('overlay'),
        isNotNull,
      );
    },
  );

  test('cancel leaves dirty sessions open and discard does not save', () async {
    final documents = DocumentSessionCoordinator(
      dataService: data,
      scratchDocument: AutomationDocument.empty(),
      streamPlans: DartStreamPlanRuntime(),
    );
    addTearDown(documents.dispose);
    final session = documents.automations.open(
      AutomationDocument.empty(),
      'one.yaml',
      unsaved: true,
    );
    session.editor.addNode('showrunner.if', GraphPoint.zero);
    expect(
      await documents.closeAutomation(
        'one.yaml',
        (_) async => DocumentCloseDecision.cancel,
      ),
      false,
    );
    expect(documents.automations.active, same(session));
    expect(
      await documents.closeAutomation(
        'one.yaml',
        (_) async => DocumentCloseDecision.discard,
      ),
      true,
    );
    expect(await documents.automationRepository('one.yaml').load(), isNull);
  });

  test(
    'an edit made during save prevents close and retains newer history',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final documents = DocumentSessionCoordinator(
        dataService: data,
        scratchDocument: AutomationDocument.empty(),
        streamPlans: DartStreamPlanRuntime(),
        automationWriter: (_, _) async {
          entered.complete();
          await release.future;
        },
      );
      addTearDown(documents.dispose);
      final session = documents.automations.open(
        AutomationDocument.empty(),
        'one.yaml',
        unsaved: true,
      );
      session.editor.addNode('showrunner.if', GraphPoint.zero);
      final closing = documents.closeAutomation(
        'one.yaml',
        (_) async => DocumentCloseDecision.save,
      );
      await entered.future;
      session.editor.addNode('showrunner.return', GraphPoint.zero);
      release.complete();
      expect(await closing, false);
      expect(documents.automations.active, same(session));
      expect(session.dirty, true);
    },
  );

  for (final type in ['Overlay', 'StreamPlan']) {
    test(
      '$type save completion cannot replace a newer document or reopen a closed one',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final documents = DocumentSessionCoordinator(
          dataService: data,
          scratchDocument: AutomationDocument.empty(),
          streamPlans: DartStreamPlanRuntime(),
          resourceWriter: (_, _) async {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          },
        );
        addTearDown(documents.dispose);
        final manager = type == 'Overlay'
            ? documents.overlays
            : documents.plans;
        const original = ResourceData(id: 'one', config: {'name': 'Original'});
        const newer = ResourceData(id: 'one', config: {'name': 'Newer'});
        manager.update(original, isDirty: true);
        final saved = documents.saveResource(type, original);
        await entered.future;
        manager.update(newer, isDirty: true);
        release.complete();
        await saved;
        expect(manager.resources['one'], same(newer));
        expect(manager.dirty['one'], true);
        manager.close('one');
        await documents.saveResource(type, original);
        expect(manager.resources, isEmpty);
      },
    );
  }
}
