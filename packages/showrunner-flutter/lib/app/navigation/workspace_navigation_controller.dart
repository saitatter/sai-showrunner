import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/showrunner_data_service.dart';
import '../workspace_document_manager.dart';
import '../workspace_registry.dart';

/// Immutable persisted navigation, never a copy of an editable document.
final class WorkspaceNavigationSnapshot {
  WorkspaceNavigationSnapshot({
    required Iterable<WorkspaceId> tabs,
    required this.selected,
    this.resourceType,
    this.resourceId,
    Iterable<String> automations = const [],
    this.selectedAutomation,
  }) : tabs = List.unmodifiable(tabs),
       automations = List.unmodifiable(automations);

  final List<WorkspaceId> tabs;
  final WorkspaceId? selected;
  final String? resourceType;
  final String? resourceId;
  final List<String> automations;
  final String? selectedAutomation;

  static bool isSafeResourceId(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains('\u0000');

  static bool isSafeAutomationFileName(String value) =>
      isSafeResourceId(value) && value.endsWith('.yaml');

  static WorkspaceId? workspaceId(String value) {
    final id = WorkspaceId(value);
    if (WorkspaceIds.all.contains(id)) return id;
    final resource =
        WorkspaceIds.overlayResourceId(id) ??
        WorkspaceIds.streamPlanResourceId(id);
    return resource != null && isSafeResourceId(resource) ? id : null;
  }

  factory WorkspaceNavigationSnapshot.fromSettings(
    Map<String, dynamic> settings,
  ) {
    final hasTabs = settings.containsKey('openWorkspaceTabs');
    final rawTabs = settings['openWorkspaceTabs'];
    final tabs = rawTabs is List
        ? rawTabs
              .whereType<String>()
              .map(workspaceId)
              .whereType<WorkspaceId>()
              .toSet()
        : hasTabs
        ? <WorkspaceId>{}
        : {WorkspaceIds.home};
    final rawAutomationTabs = settings['openAutomationTabs'];
    final files = rawAutomationTabs is List
        ? rawAutomationTabs
              .whereType<String>()
              .where(isSafeAutomationFileName)
              .toSet()
        : <String>{};
    final selected = settings['selectedWorkspace'];
    final automation = settings['selectedAutomationTab'];
    final resource = settings['selectedResourceId'];
    return WorkspaceNavigationSnapshot(
      tabs: tabs,
      selected: selected is String
          ? workspaceId(selected)
          : hasTabs
          ? null
          : WorkspaceIds.home,
      resourceType: settings['selectedResourceType'] is String
          ? settings['selectedResourceType'] as String
          : null,
      resourceId: resource is String && isSafeResourceId(resource)
          ? resource
          : null,
      automations: files,
      selectedAutomation: automation is String && files.contains(automation)
          ? automation
          : null,
    );
  }

  Map<String, dynamic> toSettings() => {
    'openWorkspaceTabs': tabs.map((id) => id.value).toList(),
    'selectedWorkspace': selected?.value,
    'openAutomationTabs': automations,
    'selectedAutomationTab': selectedAutomation,
    'selectedResourceType': resourceType,
    'selectedResourceId': resourceId,
  };
}

/// Owns restore ordering and serialized/coalesced navigation settings writes.
final class WorkspaceNavigationController extends ChangeNotifier {
  WorkspaceNavigationController({
    required this.dataService,
    required this.automationSettings,
    this.writeDelay = const Duration(milliseconds: 30),
  });

  final ShowRunnerDataService dataService;
  final Map<String, Object?> Function() automationSettings;
  final Duration writeDelay;
  final documents = WorkspaceDocumentManager(
    initial: const [WorkspaceIds.home],
  );
  String? selectedResourceType;
  String? selectedResourceId;
  String selectedPluginId = 'obs';
  Object? error;
  bool restored = false;
  bool _restoreFailed = false;
  bool _closed = false;
  final _queued = <VoidCallback>[];
  Future<void>? _restoring;
  Future<void>? _closing;
  Timer? _timer;
  Map<String, dynamic>? _pending;
  Completer<void>? _pendingCompletion;
  Future<void> _tail = Future.value();
  Future<void> _lastWrite = Future.value();

  WorkspaceNavigationSnapshot get snapshot =>
      WorkspaceNavigationSnapshot.fromSettings({
        ...documents.toSettings(),
        ...automationSettings(),
        'selectedResourceType': selectedResourceType,
        'selectedResourceId': selectedResourceId,
      });

  Future<void> restore({
    required Future<void> Function(WorkspaceNavigationSnapshot snapshot)
    restoreDocuments,
    required bool Function(WorkspaceId id) isAvailable,
  }) => _restoring ??= _restore(restoreDocuments, isAvailable);

  Future<void> _restore(
    Future<void> Function(WorkspaceNavigationSnapshot) restoreDocuments,
    bool Function(WorkspaceId) isAvailable,
  ) async {
    try {
      final saved = WorkspaceNavigationSnapshot.fromSettings(
        await dataService.loadPluginSettings('showrunner-flutter'),
      );
      await restoreDocuments(saved);
      documents.restore(
        openWorkspaces: saved.tabs.where(isAvailable),
        selected: saved.selected,
      );
      selectedResourceType = saved.resourceType;
      selectedResourceId = saved.resourceId;
    } catch (failure) {
      _restoreFailed = true;
      error = failure;
    } finally {
      restored = true;
      if (!_closed) {
        for (final action in _queued) {
          action();
        }
        notifyListeners();
      }
      _queued.clear();
    }
  }

  void openWorkspace(WorkspaceId id) => _change(() {
    if (id != WorkspaceIds.resources) {
      selectedResourceType = null;
      selectedResourceId = null;
    }
    documents.open(id);
    documents.select(id);
  });

  void openResource(String type, String? id) => _change(() {
    selectedResourceType = type;
    selectedResourceId = id;
    documents.open(WorkspaceIds.resources);
    documents.select(WorkspaceIds.resources);
  });

  void _change(VoidCallback action) {
    if (_closed) return;
    if (!restored) {
      _queued.add(action);
      return;
    }
    action();
    notifyListeners();
  }

  Future<void> persist() {
    if (_closed || !restored) return Future.value();
    if (_restoreFailed) {
      return Future.error(
        StateError(
          'Navigation settings could not be restored; refusing to overwrite them.',
        ),
      );
    }
    _pending = snapshot.toSettings();
    _pendingCompletion ??= Completer<void>();
    final result = _pendingCompletion!.future;
    _timer?.cancel();
    _timer = Timer(writeDelay, _writePending);
    return result;
  }

  void _writePending() {
    _timer?.cancel();
    _timer = null;
    final saved = _pending;
    final completion = _pendingCompletion;
    _pending = null;
    _pendingCompletion = null;
    if (saved == null || completion == null) return;
    final operation = _tail.then(
      (_) => dataService.updatePluginSettings('showrunner-flutter', saved),
    );
    _lastWrite = operation;
    _tail = operation.then<void>(
      (_) {
        completion.complete();
      },
      onError: (Object failure, StackTrace stack) {
        error = failure;
        completion.completeError(failure, stack);
      },
    );
  }

  Future<void> flush() async {
    _writePending();
    await _lastWrite;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    try {
      await _restoring;
      await flush();
    } finally {
      _queued.clear();
      super.dispose();
    }
  }
}
