import 'package:flutter/material.dart';

/// Stable identity for a top-level ShowRunner workspace.
extension type const WorkspaceId(String value) {}

abstract final class WorkspaceIds {
  static const graph = WorkspaceId('workspace.graph');
  static const plugins = WorkspaceId('workspace.plugins');
  static const diagnostics = WorkspaceId('workspace.diagnostics');
  static const automations = WorkspaceId('workspace.automations');
  static const profiles = WorkspaceId('workspace.profiles');
  static const queues = WorkspaceId('workspace.queues');
  static const resources = WorkspaceId('workspace.resources');
  static const logs = WorkspaceId('workspace.logs');
  static const about = WorkspaceId('workspace.about');
  static const settings = WorkspaceId('workspace.settings');
  static const setup = WorkspaceId('workspace.setup');
  static const variables = WorkspaceId('workspace.variables');
  static const viewerVariables = WorkspaceId('workspace.viewerVariables');
  static const remote = WorkspaceId('workspace.remote');
  static const home = WorkspaceId('workspace.home');
  static const updates = WorkspaceId('workspace.updates');
  static const chat = WorkspaceId('workspace.chat');
  static const chatCommands = WorkspaceId('workspace.chatCommands');

  static const overlayPrefix = 'workspace.overlay.';
  static const streamPlanPrefix = 'workspace.streamPlan.';

  static WorkspaceId overlay(String resourceId) =>
      WorkspaceId('$overlayPrefix$resourceId');

  static bool isOverlay(WorkspaceId id) => id.value.startsWith(overlayPrefix);

  static String? overlayResourceId(WorkspaceId id) =>
      isOverlay(id) ? id.value.substring(overlayPrefix.length) : null;

  static WorkspaceId streamPlan(String resourceId) =>
      WorkspaceId('$streamPlanPrefix$resourceId');

  static bool isStreamPlan(WorkspaceId id) =>
      id.value.startsWith(streamPlanPrefix);

  static String? streamPlanResourceId(WorkspaceId id) =>
      isStreamPlan(id) ? id.value.substring(streamPlanPrefix.length) : null;

  static const all = <WorkspaceId>[
    graph,
    plugins,
    diagnostics,
    automations,
    profiles,
    queues,
    resources,
    logs,
    about,
    settings,
    setup,
    variables,
    viewerVariables,
    remote,
    home,
    updates,
    chat,
    chatCommands,
  ];
}

enum WorkspaceCategory { application, authoring, live, resources }

final class WorkspaceDescriptor {
  const WorkspaceDescriptor({
    required this.id,
    required this.title,
    required this.icon,
    this.category = WorkspaceCategory.application,
  });

  final WorkspaceId id;
  final String title;
  final IconData icon;
  final WorkspaceCategory category;
}

const workspaceDescriptors = <WorkspaceDescriptor>[
  WorkspaceDescriptor(
    id: WorkspaceIds.chat,
    category: WorkspaceCategory.live,
    title: 'Chat',
    icon: Icons.forum_outlined,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.chatCommands,
    category: WorkspaceCategory.live,
    title: 'Chat Commands',
    icon: Icons.terminal,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.graph,
    category: WorkspaceCategory.authoring,
    title: 'Graph',
    icon: Icons.account_tree,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.plugins,
    title: 'Plugins',
    icon: Icons.extension,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.diagnostics,
    category: WorkspaceCategory.live,
    title: 'Diagnostics',
    icon: Icons.monitor_heart,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.automations,
    category: WorkspaceCategory.authoring,
    title: 'Automations',
    icon: Icons.bolt,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.profiles,
    category: WorkspaceCategory.authoring,
    title: 'Profiles',
    icon: Icons.people_alt,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.queues,
    category: WorkspaceCategory.live,
    title: 'Queues',
    icon: Icons.queue_music,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.resources,
    category: WorkspaceCategory.resources,
    title: 'Resources',
    icon: Icons.layers,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.logs,
    title: 'Logs',
    icon: Icons.receipt_long,
  ),
  WorkspaceDescriptor(id: WorkspaceIds.about, title: 'About', icon: Icons.info),
  WorkspaceDescriptor(
    id: WorkspaceIds.settings,
    title: 'Settings',
    icon: Icons.settings,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.setup,
    title: 'Setup',
    icon: Icons.rocket_launch,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.variables,
    category: WorkspaceCategory.resources,
    title: 'Variables',
    icon: Icons.data_object,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.viewerVariables,
    category: WorkspaceCategory.resources,
    title: 'Viewer Variables',
    icon: Icons.person_search_outlined,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.remote,
    category: WorkspaceCategory.live,
    title: 'Remote',
    icon: Icons.public,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.home,
    title: 'ShowRunner',
    icon: Icons.dashboard,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.updates,
    title: 'Updates',
    icon: Icons.system_update,
  ),
];

WorkspaceDescriptor workspaceDescriptorFor(WorkspaceId id) =>
    workspaceDescriptors.firstWhere(
      (descriptor) => descriptor.id == id,
      orElse: () => const WorkspaceDescriptor(
        id: WorkspaceIds.logs,
        title: 'Workspace',
        icon: Icons.dashboard,
      ),
    );
