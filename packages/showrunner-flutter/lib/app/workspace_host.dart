import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../editor/showrunner_graph_editor.dart';
import '../features/automation/automation_catalog_workspace.dart';
import '../features/dashboard/main_dashboard_workspace.dart';
import '../features/diagnostics/diagnostics_workspace.dart';
import '../features/graph/graph_workspace.dart';
import '../features/plugins/plugin_workspace.dart';
import '../features/profile/profile_workspace.dart';
import '../features/queue/queue_workspace.dart';
import '../features/remote/remote_workspace.dart';
import '../features/resources/resource_editor_registry.dart';
import '../features/resources/resources_workspace.dart';
import '../features/settings/interface_preferences.dart';
import '../features/settings/settings_workspace.dart';
import '../features/setup/setup_workspace.dart';
import '../features/support/support_workspaces.dart';
import '../features/variables/variables_workspace.dart';
import '../plugins/registry/plugin_registry.dart';
import '../plugins/runtime/provider_event_workers.dart';
import '../plugins/stream_plans/manifest.dart';
import '../plugins/variables/runtime.dart';
import '../runtime/action_queue.dart';
import '../runtime/automation_queue_manager.dart';
import '../runtime/profile_runtime.dart';
import '../schema/automation.dart';
import '../schema/resource.dart';
import '../services/showrunner_data_service.dart';
import '../services/update_check_service.dart';
import '../services/update_install_service.dart';
import 'automation_document_manager.dart';
import 'startup_health.dart';
import 'workspace_registry.dart';

/// Dependencies needed by a workspace builder, assembled once by the shell.
final class WorkspaceHostContext {
  const WorkspaceHostContext({
    required this.dataService,
    required this.graphEditor,
    required this.actionQueue,
    required this.healthFuture,
    required this.providerEvents,
    required this.pluginRegistryFuture,
    required this.profileRuntimeFuture,
    required this.showGraphEditor,
    required this.onRunNode,
    required this.onOpenAutomation,
    required this.onRepairAutomation,
    required this.onCreateAutomation,
    required this.onDeleteAutomation,
    required this.interfacePreferences,
    required this.onOpenWorkspace,
    this.queueManager,
    this.streamPlanRuntime,
    this.variableRuntime,
    this.automationDocuments,
    this.onAutomationSelected,
    this.onAutomationClosed,
    this.onAutomationReordered,
    this.profileController,
    this.profileDirty = false,
    this.onProfileDirtyChanged,
    this.onProfileEntriesChanged,
    this.onRenameProfile,
    this.onDeleteProfile,
    this.onCreateProfile,
    this.projectCatalogRevision = 0,
    this.selectedResourceType,
    this.selectedResourceId,
    this.onResourceSelected,
    this.onOpenResource,
    this.onRenameResource,
    this.onDeleteResource,
    this.onCreateResource,
    this.selectedPluginId,
    this.onPluginSelected,
    this.updateService,
    this.installService,
    this.onRestartRequested,
  });

  final ShowRunnerDataService dataService;
  final ShowRunnerGraphEditor graphEditor;
  final DartActionQueue actionQueue;
  final DartAutomationQueueManager? queueManager;
  final Future<StartupHealthSnapshot> healthFuture;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> pluginRegistryFuture;
  final Future<DartProfileRuntime> profileRuntimeFuture;
  final DartStreamPlanRuntime? streamPlanRuntime;
  final DartVariableRuntime? variableRuntime;
  final bool showGraphEditor;
  final Future<void> Function(String schemaNodeId)? onRunNode;
  final FutureOr<void> Function(AutomationData automation, String fileName)
  onOpenAutomation;
  final Future<void> Function(AutomationData automation, String fileName)
  onRepairAutomation;
  final Future<void> Function() onCreateAutomation;
  final Future<void> Function(String fileName) onDeleteAutomation;
  final FlutterInterfacePreferences interfacePreferences;
  final ValueChanged<WorkspaceId> onOpenWorkspace;
  final AutomationDocumentManager? automationDocuments;
  final ValueChanged<String>? onAutomationSelected;
  final FutureOr<void> Function(String fileName)? onAutomationClosed;
  final void Function(int oldPosition, int newPosition)? onAutomationReordered;
  final ProfileWorkspaceController? profileController;
  final bool profileDirty;
  final ValueChanged<bool>? onProfileDirtyChanged;
  final VoidCallback? onProfileEntriesChanged;
  final FutureOr<void> Function(String fileName, String name)? onRenameProfile;
  final FutureOr<void> Function(String fileName)? onDeleteProfile;
  final FutureOr<void> Function()? onCreateProfile;
  final int projectCatalogRevision;
  final String? selectedResourceType;
  final String? selectedResourceId;
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
  final String? selectedPluginId;
  final ValueChanged<String>? onPluginSelected;
  final UpdateCheckService? updateService;
  final UpdateInstallService? installService;
  final Future<bool> Function()? onRestartRequested;
}

/// Builds registered top-level workspaces without coupling the shell to pages.
final class WorkspaceRegistry {
  const WorkspaceRegistry();

  Widget build(
    BuildContext context,
    WorkspaceId id,
    WorkspaceHostContext host,
  ) => switch (id) {
    WorkspaceIds.graph =>
      host.showGraphEditor
          ? GraphWorkspace(
              editor: host.graphEditor,
              healthFuture: host.healthFuture,
              dataService: host.dataService,
              registryFuture: host.pluginRegistryFuture,
              onRunNode: host.onRunNode,
              automationDocuments: host.automationDocuments,
              onAutomationSelected: host.onAutomationSelected,
              onAutomationClosed: host.onAutomationClosed,
              onAutomationReordered: host.onAutomationReordered,
            )
          : const LogsWorkspace(),
    WorkspaceIds.plugins => PluginWorkspace(
      dataService: host.dataService,
      registryFuture: host.pluginRegistryFuture,
      providerEvents: host.providerEvents,
      selectedPluginId: host.selectedPluginId,
    ),
    WorkspaceIds.diagnostics => DiagnosticsWorkspace(
      healthFuture: host.healthFuture,
      queue: host.actionQueue,
      providerEvents: host.providerEvents,
      registryFuture: host.pluginRegistryFuture,
    ),
    WorkspaceIds.automations => AutomationCatalogWorkspace(
      dataService: host.dataService,
      onOpen: host.onOpenAutomation,
      onRepair: host.onRepairAutomation,
      onCreate: host.onCreateAutomation,
      onDelete: host.onDeleteAutomation,
    ),
    WorkspaceIds.profiles => ProfileWorkspace(
      dataService: host.dataService,
      providerEvents: host.providerEvents,
      registryFuture: host.pluginRegistryFuture,
      runtimeFuture: host.profileRuntimeFuture,
      controller: host.profileController,
      onDirtyChanged: host.onProfileDirtyChanged,
      onEntriesChanged: host.onProfileEntriesChanged,
      onCreate: host.onCreateProfile,
    ),
    WorkspaceIds.queues => QueueWorkspace(
      dataService: host.dataService,
      queue: host.actionQueue,
      queueManager: host.queueManager,
    ),
    WorkspaceIds.resources => ResourcesWorkspace(
      dataService: host.dataService,
      editorRegistry: createDefaultResourceEditorRegistry(),
      registryFuture: host.pluginRegistryFuture,
      streamPlanRuntime: host.streamPlanRuntime,
      variableRuntime: host.variableRuntime,
      resourceType: host.selectedResourceType,
      resourceId: host.selectedResourceId,
      revision: host.projectCatalogRevision,
      onCreate: host.onCreateResource,
    ),
    WorkspaceIds.logs => const LogsWorkspace(),
    WorkspaceIds.about => const AboutWorkspace(),
    WorkspaceIds.updates => UpdateWorkspace(
      updateService: host.updateService,
      installService: host.installService,
      onRestartRequested: host.onRestartRequested,
      downloadDirectory: Directory(
        '${host.dataService.userDirectory.path}/updates',
      ),
    ),
    WorkspaceIds.settings => SettingsWorkspace(
      preferences: host.interfacePreferences,
      registryFuture: host.pluginRegistryFuture,
      dataService: host.dataService,
    ),
    WorkspaceIds.setup => SetupWorkspace(
      dataService: host.dataService,
      onOpenPlugin: (pluginId) {
        host.onPluginSelected?.call(pluginId);
        host.onOpenWorkspace(WorkspaceIds.plugins);
      },
    ),
    WorkspaceIds.variables => VariablesWorkspace(
      dataService: host.dataService,
      eventHub: host.providerEvents.eventHub,
      variableRuntime: host.variableRuntime,
    ),
    WorkspaceIds.remote => RemoteWorkspace(
      dataService: host.dataService,
      registryFuture: host.pluginRegistryFuture,
    ),
    WorkspaceIds.home => MainDashboardWorkspace(
      dataService: host.dataService,
      actionQueue: host.actionQueue,
      providerEvents: host.providerEvents,
      registryFuture: host.pluginRegistryFuture,
      streamPlanRuntime: host.streamPlanRuntime,
      onOpenWorkspace: host.onOpenWorkspace,
    ),
    _ => const LogsWorkspace(),
  };
}
