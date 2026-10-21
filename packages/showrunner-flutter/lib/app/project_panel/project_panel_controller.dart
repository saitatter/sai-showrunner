part of '../project_panel.dart';

/// Commands and navigation callbacks used by the project panel.
///
/// Keeping these together makes the panel's widget contract readable while
/// preserving the same callback behavior for the application shell.
final class ProjectPanelCallbacks {
  const ProjectPanelCallbacks({
    required this.onDestinationSelected,
    required this.onPluginSelected,
    required this.onPluginToggle,
    this.onOpenAutomation,
    this.onOpenProfile,
    this.onResourceSelected,
    this.onOpenResource,
    this.onRenameAutomation,
    this.onDeleteAutomation,
    this.onCreateAutomation,
    this.onRenameProfile,
    this.onDeleteProfile,
    this.onCreateProfile,
    this.onRenameResource,
    this.onDeleteResource,
    this.onCreateResource,
  });

  final ValueChanged<WorkspaceId> onDestinationSelected;
  final ValueChanged<String> onPluginSelected;
  final Future<void> Function(String pluginId, bool enabled) onPluginToggle;
  final FutureOr<void> Function(AutomationDocument automation, String fileName)?
  onOpenAutomation;
  final FutureOr<void> Function(String fileName)? onOpenProfile;
  final ValueChanged<String>? onResourceSelected;
  final FutureOr<void> Function(ResourceData resource, String resourceType)?
  onOpenResource;
  final FutureOr<void> Function(String fileName, String name)?
  onRenameAutomation;
  final FutureOr<void> Function(String fileName)? onDeleteAutomation;
  final FutureOr<void> Function()? onCreateAutomation;
  final FutureOr<void> Function(String fileName, String name)? onRenameProfile;
  final FutureOr<void> Function(String fileName)? onDeleteProfile;
  final FutureOr<void> Function()? onCreateProfile;
  final FutureOr<void> Function(
    ResourceData resource,
    String resourceType,
    String name,
  )?
  onRenameResource;
  final FutureOr<void> Function(ResourceData resource, String resourceType)?
  onDeleteResource;
  final FutureOr<void> Function(String resourceType)? onCreateResource;
}

/// Owns project-panel state that is independent from the widget tree.
///
/// Catalog loading and group expansion used to be mixed into a 1,500-line
/// widget. The controller keeps those state transitions testable and lets the
/// view sections remain stateless.
final class ProjectPanelController extends ChangeNotifier {
  ProjectPanelController({
    required ShowRunnerProjectCatalogService? catalogService,
    required this.catalogRevision,
  }) : _catalogService = catalogService,
       _expanded = {
         'automations': false,
         'profiles': false,
         'stream-plans': false,
         'overlays': false,
         // Keep the top-level catalog closed on a clean start. The preference
         // with a similar name belongs to the category rows inside it.
         'integrations': false,
         'audio': false,
         'dashboards': false,
         'tools': false,
       } {
    _catalogFuture = _loadCatalog(catalogService);
    _watchCatalog();
  }

  ShowRunnerProjectCatalogService? _catalogService;
  int catalogRevision;
  Future<ShowRunnerProjectCatalog>? _catalogFuture;
  final Map<String, bool> _expanded;
  StreamSubscription? _catalogChanges;
  Timer? _catalogTimer;
  bool _closed = false;
  Future<void>? _closing;
  PersistenceIssue? watchIssue;
  int _watchGeneration = 0;
  final Set<Future<void>> _watchStops = {};
  final Set<Future<ShowRunnerProjectCatalog>> _catalogLoads = {};

  Future<ShowRunnerProjectCatalog>? _loadCatalog(
    ShowRunnerProjectCatalogService? service,
  ) {
    if (service == null || _closed) return null;
    final loading = service.load();
    _catalogLoads.add(loading);
    loading.then<void>(
      (_) {
        _catalogLoads.remove(loading);
      },
      onError: (Object _, StackTrace _) {
        _catalogLoads.remove(loading);
      },
    );
    return loading;
  }

  final List<Object> _watchStopErrors = [];

  void _retireWatcher(StreamSubscription subscription) {
    final stopped = Future<void>.sync(subscription.cancel).then<void>(
      (_) {},
      onError: (Object error) {
        _watchStopErrors.add(error);
      },
    );
    _watchStops.add(stopped);
    stopped.then((_) => _watchStops.remove(stopped));
  }

  void _watchCatalog() {
    final service = _catalogService;
    if (service == null || _closed) return;
    final generation = ++_watchGeneration;
    _catalogChanges = service.watchChanges().listen(
      (_) {
        if (_closed || generation != _watchGeneration) return;
        _catalogTimer?.cancel();
        _catalogTimer = Timer(const Duration(milliseconds: 50), () {
          if (_closed || generation != _watchGeneration) return;
          _catalogFuture = _loadCatalog(_catalogService);
          notifyListeners();
        });
      },
      onError: (Object error) {
        if (_closed || generation != _watchGeneration) return;
        watchIssue = PersistenceIssue.fromError(
          error,
          owner: 'catalog',
          document: 'watcher',
        );
        notifyListeners();
      },
    );
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _catalogTimer?.cancel();
    _watchGeneration++;
    if (_catalogChanges case final subscription?) _retireWatcher(subscription);
    _catalogChanges = null;
    await Future.wait([
      ..._watchStops,
      for (final loading in _catalogLoads.toList()) loading.then<void>((_) {}),
    ]);
    if (_watchStopErrors.isNotEmpty) {
      throw StateError('A project catalog watcher could not be stopped.');
    }
  }

  @override
  void dispose() {
    unawaited(
      close().catchError((Object error, StackTrace stack) {
        ShowRunnerLogger.instance.error(
          'persistence',
          'Could not close the project catalog watcher.',
          error: error,
          stackTrace: stack,
        );
      }),
    );
    super.dispose();
  }

  Future<ShowRunnerProjectCatalog>? get catalogFuture => _catalogFuture;

  bool isExpanded(String id) => _expanded[id] ?? false;

  void toggle(String id) {
    _expanded[id] = !isExpanded(id);
    notifyListeners();
  }

  void updateCatalog({
    required ShowRunnerProjectCatalogService? service,
    required int revision,
  }) {
    if (_catalogService == service && catalogRevision == revision) {
      return;
    }
    if (_closed) return;
    final changed = _catalogService != service;
    if (changed) {
      _catalogTimer?.cancel();
      final previous = _catalogChanges;
      if (previous != null) _retireWatcher(previous);
      _catalogChanges = null;
      watchIssue = null;
    }
    _catalogService = service;
    if (changed) _watchCatalog();
    catalogRevision = revision;
    _catalogFuture = _loadCatalog(service);
    notifyListeners();
  }
}
