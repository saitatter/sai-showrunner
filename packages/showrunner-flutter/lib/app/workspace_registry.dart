import 'package:flutter/material.dart';

/// Stable identity for a top-level ShowRunner workspace.
///
/// Workspace identities are persisted as their historical numeric values only
/// at the settings boundary. Application and widget code uses these IDs so
/// removing or reordering a workspace cannot silently route to another page.
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
  static const remote = WorkspaceId('workspace.remote');
  static const home = WorkspaceId('workspace.home');
  static const updates = WorkspaceId('workspace.updates');

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
    remote,
    home,
    updates,
  ];

  /// Converts the pre-registry settings representation at the persistence
  /// boundary. This is the only application code that knows those numbers.
  static WorkspaceId? fromLegacyIndex(int index) => switch (index) {
    0 => graph,
    1 => plugins,
    2 => diagnostics,
    3 => automations,
    4 => profiles,
    5 => queues,
    6 => resources,
    7 => logs,
    8 => about,
    9 => settings,
    10 => setup,
    11 => variables,
    12 => remote,
    13 => home,
    14 => updates,
    _ => null,
  };

  static int legacyIndex(WorkspaceId id) => switch (id) {
    graph => 0,
    plugins => 1,
    diagnostics => 2,
    automations => 3,
    profiles => 4,
    queues => 5,
    resources => 6,
    logs => 7,
    about => 8,
    settings => 9,
    setup => 10,
    variables => 11,
    remote => 12,
    home => 13,
    updates => 14,
    _ => throw ArgumentError('Unknown workspace: ${id.value}'),
  };
}

final class WorkspaceDescriptor {
  const WorkspaceDescriptor({
    required this.id,
    required this.title,
    required this.icon,
  });

  final WorkspaceId id;
  final String title;
  final IconData icon;
}

const workspaceDescriptors = <WorkspaceDescriptor>[
  WorkspaceDescriptor(
    id: WorkspaceIds.graph,
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
    title: 'Diagnostics',
    icon: Icons.monitor_heart,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.automations,
    title: 'Automations',
    icon: Icons.bolt,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.profiles,
    title: 'Profiles',
    icon: Icons.people_alt,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.queues,
    title: 'Queues',
    icon: Icons.queue_music,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.resources,
    title: 'Resources',
    icon: Icons.layers,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.logs,
    title: 'Logs',
    icon: Icons.receipt_long,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.about,
    title: 'About',
    icon: Icons.info,
  ),
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
    title: 'Variables',
    icon: Icons.data_object,
  ),
  WorkspaceDescriptor(
    id: WorkspaceIds.remote,
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
