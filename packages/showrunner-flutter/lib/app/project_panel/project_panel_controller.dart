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
  final FutureOr<void> Function(AutomationData automation, String fileName)?
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
    required bool expandIntegrationCategories,
  }) : _catalogService = catalogService,
       _expanded = {
         'automations': false,
         'profiles': false,
         'stream-plans': false,
         'overlays': false,
         'integrations': expandIntegrationCategories,
         'audio': false,
         'dashboards': false,
         'tools': false,
       } {
    _catalogFuture = catalogService?.load();
  }

  ShowRunnerProjectCatalogService? _catalogService;
  int catalogRevision;
  Future<ShowRunnerProjectCatalog>? _catalogFuture;
  final Map<String, bool> _expanded;

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
    if (identical(_catalogService, service) && catalogRevision == revision) {
      return;
    }
    _catalogService = service;
    catalogRevision = revision;
    _catalogFuture = service?.load();
    notifyListeners();
  }
}
