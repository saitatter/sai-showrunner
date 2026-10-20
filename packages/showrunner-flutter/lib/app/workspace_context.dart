import '../graph/domain/automation_document.dart';
import 'dart:async';
import '../features/chat/unified_chat_runtime.dart';
import '../features/chat/chat_dock_service.dart';

import 'package:flutter/material.dart';

import 'commands/app_command.dart';
import '../graph/controller/automation_document_sessions.dart';
import '../app/startup_health.dart';
import 'workspace_registry.dart';
import '../graph/controller/automation_editor_controller.dart';
import '../graph/ui/automation_graph_workspace.dart';
import '../graph/execution/showrunner_execution_visual_adapter.dart';
import '../features/profile/profile_workspace.dart';
import '../features/settings/interface_preferences.dart';
import '../plugins/runtime/provider_event_workers.dart';
import '../plugins/registry/plugin_registry.dart';
import '../plugins/overlays/overlay_presence.dart';
import '../plugins/obs/overlay_source_service.dart';
import '../plugins/stream_plans/manifest.dart';
import '../plugins/variables/runtime.dart';
import '../runtime/action_queue.dart';
import '../runtime/automation_queue_manager.dart';
import '../schema/resource.dart';
import '../runtime/profile_runtime.dart';
import '../services/showrunner_data_service.dart';
import '../services/update_check_service.dart';
import '../services/update_install_service.dart';

// Immutable capability bundles. Mutable services/controllers are borrowed;
// document maps and tab lists are snapshots owned by their coordinators.
@immutable
final class RuntimeStatusSources {
  const RuntimeStatusSources({
    required this.dataService,
    required this.actionQueue,
    this.queueManager,
    required this.healthFuture,
    required this.providerEvents,
    this.chatRuntime,
    this.chatDock,
    required this.pluginRegistryFuture,
    this.overlayPresenceReaderFuture,
    this.overlayObsSourceService,
    required this.profileRuntimeFuture,
    this.streamPlanRuntime,
    this.variableRuntime,
  });
  final ShowRunnerDataService dataService;
  final DartActionQueue actionQueue;
  final DartAutomationQueueManager? queueManager;
  final Future<StartupHealthSnapshot> healthFuture;
  final ProviderEventRuntime providerEvents;
  final UnifiedChatRuntime? chatRuntime;
  final ChatDockService? chatDock;
  final Future<DartPluginRegistry> pluginRegistryFuture;
  final Future<OverlayPresenceReader?>? overlayPresenceReaderFuture;
  final OverlayObsSourceActions? overlayObsSourceService;
  final Future<DartProfileRuntime> profileRuntimeFuture;
  final DartStreamPlanRuntime? streamPlanRuntime;
  final DartVariableRuntime? variableRuntime;
}

@immutable
final class GraphWorkspacePorts {
  const GraphWorkspacePorts({
    required this.graphEditor,
    this.graphCanvasKey,
    this.graphExecution,
    this.onRunGraph,
    required this.showGraphEditor,
    required this.onRunNode,
    required this.activeAutomationFile,
    this.activeAutomationDirty = false,
    this.automationDocuments,
    this.onAutomationSelected,
    this.onAutomationClosed,
    this.onAutomationReordered,
  });
  final AutomationEditorController graphEditor;
  final GlobalKey<AutomationGraphWorkspaceState>? graphCanvasKey;
  final ShowrunnerExecutionVisualAdapter? graphExecution;
  final Future<void> Function()? onRunGraph;
  final bool showGraphEditor;
  final Future<void> Function(String schemaNodeId)? onRunNode;
  final String? activeAutomationFile;
  final bool activeAutomationDirty;
  final AutomationDocumentSessions? automationDocuments;
  final ValueChanged<String>? onAutomationSelected;
  final FutureOr<void> Function(String fileName)? onAutomationClosed;
  final void Function(int oldPosition, int newPosition)? onAutomationReordered;
}

@immutable
final class WorkspaceNavigationState {
  WorkspaceNavigationState({
    required this.selectedWorkspace,
    List<WorkspaceId> openWorkspaces = const [WorkspaceIds.graph],
    required this.onDestinationSelected,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabReordered,
    this.selectedPluginId,
    this.onPluginSelected,
    this.selectedResourceType,
    this.selectedResourceId,
  }) : openWorkspaces = List.unmodifiable(openWorkspaces);
  final WorkspaceId selectedWorkspace;
  final List<WorkspaceId> openWorkspaces;
  final ValueChanged<WorkspaceId> onDestinationSelected;
  final ValueChanged<WorkspaceId>? onTabSelected;
  final FutureOr<void> Function(WorkspaceId)? onTabClosed;
  final void Function(int oldPosition, int newPosition)? onTabReordered;
  final String? selectedPluginId;
  final ValueChanged<String>? onPluginSelected;
  final String? selectedResourceType;
  final String? selectedResourceId;
}

@immutable
final class ResourceWorkspacePorts {
  ResourceWorkspacePorts({
    this.projectCatalogRevision = 0,
    this.onResourceSelected,
    this.onOpenResource,
    this.onRenameResource,
    this.onDeleteResource,
    this.onCreateResource,
    Map<String, ResourceData> overlayResources = const <String, ResourceData>{},
    Map<String, bool> overlayDirty = const <String, bool>{},
    this.onSaveOverlay,
    this.onOverlayDirtyChanged,
    this.onOverlayDocumentChanged,
    Map<String, ResourceData> streamPlanResources =
        const <String, ResourceData>{},
    Map<String, bool> streamPlanDirty = const <String, bool>{},
    this.onSaveStreamPlan,
    this.onStreamPlanDocumentChanged,
  }) : overlayResources = Map.unmodifiable(overlayResources),
       overlayDirty = Map.unmodifiable(overlayDirty),
       streamPlanResources = Map.unmodifiable(streamPlanResources),
       streamPlanDirty = Map.unmodifiable(streamPlanDirty);
  final int projectCatalogRevision;
  final ValueChanged<String>? onResourceSelected;
  final FutureOr<void> Function(ResourceData resource, String resourceType)?
  onOpenResource;
  final FutureOr<void> Function(
    ResourceData resource,
    String resourceType,
    String name,
  )?
  onRenameResource;
  final FutureOr<void> Function(ResourceData resource, String resourceType)?
  onDeleteResource;
  final FutureOr<void> Function(String resourceType)? onCreateResource;
  final Map<String, ResourceData> overlayResources;
  final Map<String, bool> overlayDirty;
  final Future<void> Function(ResourceData resource)? onSaveOverlay;
  final void Function(String resourceId, bool dirty)? onOverlayDirtyChanged;
  final void Function(ResourceData resource, bool dirty)?
  onOverlayDocumentChanged;
  final Map<String, ResourceData> streamPlanResources;
  final Map<String, bool> streamPlanDirty;
  final Future<void> Function(ResourceData resource)? onSaveStreamPlan;
  final void Function(ResourceData resource, bool dirty)?
  onStreamPlanDocumentChanged;
}

@immutable
final class ProfileWorkspacePorts {
  const ProfileWorkspacePorts({
    this.profileController,
    this.profileDirty = false,
    this.onProfileDirtyChanged,
    this.onProfileEntriesChanged,
    this.onRenameProfile,
    this.onDeleteProfile,
    this.onCreateProfile,
  });
  final ProfileWorkspaceController? profileController;
  final bool profileDirty;
  final ValueChanged<bool>? onProfileDirtyChanged;
  final VoidCallback? onProfileEntriesChanged;
  final FutureOr<void> Function(String fileName, String name)? onRenameProfile;
  final FutureOr<void> Function(String fileName)? onDeleteProfile;
  final FutureOr<void> Function()? onCreateProfile;
}

@immutable
final class AutomationWorkspaceActions {
  const AutomationWorkspaceActions({
    required this.onOpenAutomation,
    this.onRenameAutomation,
    this.onDeleteAutomationItem,
    required this.onRepairAutomation,
    required this.onCreateAutomation,
    required this.onDeleteAutomation,
  });
  final FutureOr<void> Function(AutomationDocument automation, String fileName)
  onOpenAutomation;
  final FutureOr<void> Function(String fileName, String name)?
  onRenameAutomation;
  final FutureOr<void> Function(String fileName)? onDeleteAutomationItem;
  final Future<void> Function(AutomationDocument automation, String fileName)
  onRepairAutomation;
  final Future<void> Function() onCreateAutomation;
  final Future<void> Function(String fileName) onDeleteAutomation;
}

@immutable
final class WorkspaceSupportPorts {
  const WorkspaceSupportPorts({
    this.updateService,
    this.installService,
    this.onRestartRequested,
  });
  final UpdateCheckService? updateService;
  final UpdateInstallService? installService;
  final Future<bool> Function()? onRestartRequested;
}

final class WorkspaceHostContext {
  const WorkspaceHostContext({
    required this.runtime,
    required this.graph,
    required this.navigation,
    required this.resources,
    required this.profiles,
    required this.automations,
    required this.support,
    required this.interfacePreferences,
    required this.commands,
  });
  final RuntimeStatusSources runtime;
  final GraphWorkspacePorts graph;
  final WorkspaceNavigationState navigation;
  final ResourceWorkspacePorts resources;
  final ProfileWorkspacePorts profiles;
  final AutomationWorkspaceActions automations;
  final WorkspaceSupportPorts support;
  final FlutterInterfacePreferences interfacePreferences;
  final AppCommandRegistry commands;
}
