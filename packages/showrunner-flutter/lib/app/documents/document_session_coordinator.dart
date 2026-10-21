import '../../persistence/document_revision.dart';
import '../../services/structured_logger.dart';
import 'dart:async';

import '../../schema/identifiers.dart';
import '../../graph/controller/automation_document_sessions.dart';
import '../../graph/controller/automation_editor_controller.dart';
import '../../graph/domain/automation_document.dart';
import '../../persistence/automation_repository.dart';
import '../../persistence/resource_repository.dart';
import '../../plugins/stream_plans/manifest.dart';
import '../../plugins/dashboards/cloud_sync.dart';
import '../../schema/resource.dart';
import '../../schema/stream_plan.dart';
import '../../services/showrunner_data_service.dart';
import '../navigation/workspace_navigation_controller.dart';
import '../resource_document_manager.dart';
import '../workspace_registry.dart';

enum DocumentCloseDecision { save, discard, cancel }

typedef DocumentClosePrompt =
    Future<DocumentCloseDecision> Function(String name);

/// Owns editor sessions and repository operations, never a second graph model.
final class DocumentSessionCoordinator {
  DocumentSessionCoordinator({
    required this.dataService,
    required AutomationDocument scratchDocument,
    required this.streamPlans,
    this.automationWriter,
    this.resourceWriter,
    this.canEditResource,
  }) : scratch = AutomationEditorController(document: scratchDocument);

  final ShowRunnerDataService dataService;
  final DartStreamPlanRuntime streamPlans;
  final Future<void> Function(String fileName, AutomationDocument document)?
  automationWriter;
  final Future<void> Function(String type, ResourceData resource)?
  resourceWriter;
  final Future<bool> Function(String type)? canEditResource;
  final automations = AutomationDocumentSessions();
  final overlays = ResourceDocumentManager();
  final plans = ResourceDocumentManager();
  final AutomationEditorController scratch;
  bool _disposed = false;
  final _pending = <Future<void>>{};
  final _cancelPrompts = Completer<DocumentCloseDecision>();
  Future<void>? _closeFuture;
  AutomationEditorController get activeEditor =>
      automations.active?.editor ?? scratch;
  bool get hasUnsavedChanges =>
      automations.documents.any((session) => session.dirty) ||
      overlays.hasUnsavedChanges ||
      plans.hasUnsavedChanges;

  AutomationRepository automationRepository(String fileName) {
    if (!WorkspaceNavigationSnapshot.isSafeAutomationFileName(fileName)) {
      throw ArgumentError.value(fileName, 'fileName');
    }
    return dataService.storage.automation(fileName);
  }

  ResourceRepository resourceRepository(String type) =>
      dataService.storage.resource(ResourceTypeId(type));

  Future<void> restore(
    WorkspaceNavigationSnapshot saved, {
    required bool showGraphEditor,
  }) async {
    if (showGraphEditor) {
      for (final file in saved.automations) {
        try {
          final document = await automationRepository(file).load();
          if (document != null && !_disposed) automations.open(document, file);
        } catch (error, stack) {
          ShowRunnerLogger.instance.error(
            'navigation',
            'Could not restore automation $file',
            error: error,
            stackTrace: stack,
          );
        }
      }
      if (saved.selectedAutomation case final file?) automations.activate(file);
    }
    for (final tab in saved.tabs) {
      final overlay = WorkspaceIds.overlayResourceId(tab);
      final plan = WorkspaceIds.streamPlanResourceId(tab);
      final id = overlay ?? plan;
      if (id == null) continue;
      try {
        final resource = await resourceRepository(
          overlay != null ? 'Overlay' : 'StreamPlan',
        ).load(id);
        if (resource != null && !_disposed) {
          (overlay != null ? overlays : plans).open(resource);
        }
      } catch (error, stack) {
        ShowRunnerLogger.instance.error(
          'navigation',
          'Could not restore resource $id',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }

  Future<T> _track<T>(Future<T> Function() operation) {
    if (_closeFuture != null || _disposed) {
      return Future.error(StateError('Document sessions are closed.'));
    }
    final result = Future<T>.sync(operation);
    final pending = result.then<void>((_) {});
    _pending.add(pending);
    pending.then<void>(
      (_) {
        _pending.remove(pending);
      },
      onError: (Object _, StackTrace _) {
        _pending.remove(pending);
      },
    );
    return result;
  }

  Future<DocumentCloseDecision> _prompt(
    String name,
    DocumentClosePrompt prompt,
  ) => Future.any([prompt(name), _cancelPrompts.future]);
  Future<void> flush() => Future.wait(_pending.toList()).then<void>((_) {});
  Future<void> saveAutomation(
    AutomationEditorSession session, {
    AutomationDocument? document,
  }) => _track(() => _saveAutomation(session, document: document));
  Future<void> saveResource(String type, ResourceData resource) =>
      _track(() => _saveResource(type, resource));
  Future<void> saveAll() => _track(_saveAll);

  Future<void> _saveAutomation(
    AutomationEditorSession session, {
    AutomationDocument? document,
  }) async {
    final saved = document ?? session.data;
    final revision = session.editor.graph.revision;
    if (automationWriter case final writer?) {
      await writer(session.fileName, saved);
    } else {
      await automationRepository(session.fileName).save(
        saved,
        expectedRevision: session.storageRevision,
        requireAbsent: session.storageRevision == null,
      );
    }
    if (!_disposed && identical(automations.find(session.fileName), session)) {
      session.storageRevision = DocumentRevision.of(saved.toJson());
      automations.markSaved(session.fileName, revision: revision);
    }
  }

  Future<void> _requireResourceOwner(String type) async {
    if (canEditResource != null && !await canEditResource!(type)) {
      throw StateError(
        'The owning resource plugin is unavailable or disabled.',
      );
    }
  }

  Future<void> _saveResource(String type, ResourceData resource) async {
    await _requireResourceOwner(type);
    final manager = type == 'Overlay' ? overlays : plans;
    final expected = manager.resources[resource.id];
    final storageRevision = manager.storageRevisions[resource.id];
    if (resourceWriter case final writer?) {
      await writer(type, resource);
    } else {
      await resourceRepository(type).save(
        resource,
        expectedRevision: storageRevision,
        requireAbsent: storageRevision == null,
      );
    }
    if (!_disposed) {
      manager.acceptPersisted(resource, storageRevision);
      manager.markSavedIfCurrent(resource, expected);
    }
    if (!_disposed &&
        type == 'StreamPlan' &&
        streamPlans.activePlanId == resource.id) {
      await streamPlans.updateActivePlan(
        resource.id,
        StreamPlanData.fromConfig(resource.config),
      );
    }
  }

  Future<void> _saveAll() async {
    for (final session in automations.documents.toList()) {
      if (session.dirty) await _saveAutomation(session);
    }
    for (final (type, manager) in [
      ('Overlay', overlays),
      ('StreamPlan', plans),
    ]) {
      for (final resource in manager.resources.values.toList()) {
        if (manager.dirty[resource.id] == true) {
          await _saveResource(type, resource);
        }
      }
    }
  }

  Future<bool> confirmAutomation(
    String fileName,
    DocumentClosePrompt prompt,
  ) async {
    final session = automations.find(fileName);
    if (session == null || !session.dirty) return true;
    final decision = await _prompt(fileName, prompt);
    if (_disposed ||
        _closeFuture != null ||
        !identical(automations.find(fileName), session)) {
      return false;
    }
    if (decision == DocumentCloseDecision.cancel) return false;
    if (decision == DocumentCloseDecision.save) {
      await saveAutomation(session);
      return !session.dirty;
    }
    return true;
  }

  Future<bool> confirmResource(
    String type,
    String id,
    DocumentClosePrompt prompt,
  ) async {
    final manager = type == 'Overlay' ? overlays : plans;
    final resource = manager.resources[id];
    if (resource == null || manager.dirty[id] != true) return true;
    final decision = await _prompt(resource.name, prompt);
    if (_disposed ||
        _closeFuture != null ||
        !identical(manager.resources[id], resource)) {
      return false;
    }
    if (decision == DocumentCloseDecision.cancel) return false;
    if (decision == DocumentCloseDecision.save) {
      await saveResource(type, resource);
      return manager.dirty[id] != true;
    }
    return true;
  }

  Future<bool> confirmWorkspace(
    WorkspaceId workspace,
    DocumentClosePrompt prompt,
  ) async {
    if (workspace == WorkspaceIds.graph) {
      final file = automations.activeFileName;
      if (file != null) return confirmAutomation(file, prompt);
    }
    if (WorkspaceIds.overlayResourceId(workspace) case final id?) {
      return confirmResource('Overlay', id, prompt);
    }
    if (WorkspaceIds.streamPlanResourceId(workspace) case final id?) {
      return confirmResource('StreamPlan', id, prompt);
    }
    return true;
  }

  Future<bool> closeAutomation(String fileName, DocumentClosePrompt prompt) =>
      _track(() => _closeAutomation(fileName, prompt));
  Future<bool> deleteAutomation(String fileName, DocumentClosePrompt prompt) =>
      _track(() => _deleteAutomation(fileName, prompt));
  Future<bool> deleteResource(
    ResourceData resource,
    String type,
    DocumentClosePrompt prompt,
  ) => _track(() => _deleteResource(resource, type, prompt));

  Future<bool> _closeAutomation(
    String fileName,
    DocumentClosePrompt prompt,
  ) async {
    if (automations.find(fileName) == null) return false;
    final wasActive = automations.activeFileName == fileName;
    if (!await confirmAutomation(fileName, prompt)) return false;
    automations.close(fileName);
    if (wasActive && automations.active == null) {
      scratch.load(AutomationDocument.empty());
    }
    return true;
  }

  Future<bool> _deleteAutomation(
    String fileName,
    DocumentClosePrompt prompt,
  ) async {
    final wasActive = automations.activeFileName == fileName;
    if (!await confirmAutomation(fileName, prompt)) return false;
    final expected = automations.find(fileName)?.storageRevision;
    await automationRepository(fileName).delete(expectedRevision: expected);
    automations.close(fileName);
    if (wasActive && automations.active == null) {
      scratch.load(AutomationDocument.empty());
    }
    return true;
  }

  Future<bool> _deleteResource(
    ResourceData resource,
    String type,
    DocumentClosePrompt prompt,
  ) async {
    await _requireResourceOwner(type);
    if ((type == 'Overlay' || type == 'StreamPlan') &&
        !await confirmResource(type, resource.id, prompt)) {
      return false;
    }
    if (type == 'Dashboard') {
      await DashboardCloudSyncService(dataService: dataService).synchronize(
        ResourceData(
          id: resource.id,
          config: {...resource.config, 'remoteTwitchIds': const <String>[]},
          state: resource.state,
        ),
      );
    }
    final manager = type == 'Overlay'
        ? overlays
        : type == 'StreamPlan'
        ? plans
        : null;
    await resourceRepository(type).delete(
      resource.id,
      expectedRevision:
          manager?.storageRevisions[resource.id] ??
          DocumentRevision.of(resource.toJson()),
    );
    if (type == 'Overlay') overlays.close(resource.id);
    if (type == 'StreamPlan') plans.close(resource.id);
    return true;
  }

  Future<bool> confirmAllClose(DocumentClosePrompt prompt) async {
    final names = [
      for (final session in automations.documents)
        if (session.dirty) session.fileName,
      for (final manager in [overlays, plans])
        for (final resource in manager.resources.values)
          if (manager.dirty[resource.id] == true) resource.name,
    ];
    if (names.isEmpty) return true;
    final decision = await _prompt(names.join(', '), prompt);
    if (_disposed ||
        _closeFuture != null ||
        decision == DocumentCloseDecision.cancel) {
      return false;
    }
    if (decision == DocumentCloseDecision.save) {
      await saveAll();
      return !hasUnsavedChanges;
    }
    return true;
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _cancelPrompts.complete(DocumentCloseDecision.cancel);
    try {
      await flush();
    } finally {
      dispose();
      await Future.wait([
        automations.teardownComplete,
        scratch.teardownComplete,
      ]);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    automations.dispose();
    scratch.dispose();
  }
}
