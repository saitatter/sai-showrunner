import 'package:flutter/material.dart';
import 'workspace_context.dart';
import 'workspace_registry.dart';
import '../features/chat/workspace_registration.dart' as features_chat;
import '../graph/ui/workspace_registration.dart' as graph_ui;
import '../features/automation/workspace_registration.dart'
    as features_automation;
import '../features/plugins/workspace_registration.dart' as features_plugins;
import '../features/diagnostics/workspace_registration.dart'
    as features_diagnostics;
import '../features/profile/workspace_registration.dart' as features_profile;
import '../features/queue/workspace_registration.dart' as features_queue;
import '../features/resources/workspace_registration.dart'
    as features_resources;
import '../features/support/workspace_registration.dart' as features_support;
import '../features/settings/workspace_registration.dart' as features_settings;
import '../features/setup/workspace_registration.dart' as features_setup;
import '../features/variables/workspace_registration.dart'
    as features_variables;
import '../features/remote/workspace_registration.dart' as features_remote;
import '../features/dashboard/workspace_registration.dart'
    as features_dashboard;

typedef WorkspaceBuilder =
    Widget Function(BuildContext context, WorkspaceHostContext host);

final class WorkspaceRegistration {
  const WorkspaceRegistration(this.descriptor, this.builder);
  final WorkspaceDescriptor descriptor;
  final WorkspaceBuilder builder;
}

/// Deterministic feature registrations; no service locator or dynamic loading.
final class WorkspaceRegistry {
  const WorkspaceRegistry({this.builders = defaultBuilders});
  final Map<WorkspaceId, WorkspaceBuilder> builders;
  static const defaultBuilders = <WorkspaceId, WorkspaceBuilder>{
    WorkspaceIds.chat: features_chat.buildChatWorkspace,
    WorkspaceIds.chatCommands: features_chat.buildChatCommandsWorkspace,
    WorkspaceIds.graph: graph_ui.buildGraphWorkspace,
    WorkspaceIds.automations: features_automation.buildAutomationsWorkspace,
    WorkspaceIds.plugins: features_plugins.buildPluginsWorkspace,
    WorkspaceIds.diagnostics: features_diagnostics.buildDiagnosticsWorkspace,
    WorkspaceIds.profiles: features_profile.buildProfilesWorkspace,
    WorkspaceIds.queues: features_queue.buildQueuesWorkspace,
    WorkspaceIds.resources: features_resources.buildResourcesWorkspace,
    WorkspaceIds.logs: features_support.buildLogsWorkspace,
    WorkspaceIds.about: features_support.buildAboutWorkspace,
    WorkspaceIds.updates: features_support.buildUpdatesWorkspace,
    WorkspaceIds.settings: features_settings.buildSettingsWorkspace,
    WorkspaceIds.setup: features_setup.buildSetupWorkspace,
    WorkspaceIds.variables: features_variables.buildVariablesWorkspace,
    WorkspaceIds.viewerVariables:
        features_variables.buildViewerVariablesWorkspace,
    WorkspaceIds.remote: features_remote.buildRemoteWorkspace,
    WorkspaceIds.home: features_dashboard.buildHomeWorkspace,
  };

  WorkspaceRegistration resolve(WorkspaceId id) {
    if (WorkspaceIds.isOverlay(id) || WorkspaceIds.isStreamPlan(id)) {
      return WorkspaceRegistration(
        WorkspaceDescriptor(
          id: id,
          title: WorkspaceIds.isOverlay(id) ? 'Overlay' : 'Stream Plan',
          icon: Icons.layers,
          category: WorkspaceCategory.resources,
        ),
        (context, host) =>
            features_resources.buildResourceDocumentWorkspace(
              context,
              id,
              host,
            ) ??
            features_support.buildLogsWorkspace(context, host),
      );
    }
    return WorkspaceRegistration(
      workspaceDescriptorFor(id),
      builders[id] ?? features_support.buildLogsWorkspace,
    );
  }

  Widget build(
    BuildContext context,
    WorkspaceId id,
    WorkspaceHostContext host,
  ) {
    return resolve(id).builder(context, host);
  }
}
