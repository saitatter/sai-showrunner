import 'package:flutter/material.dart';

import 'profile_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildProfilesWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => ProfileWorkspace(
  dataService: host.runtime.dataService,
  providerEvents: host.runtime.providerEvents,
  registryFuture: host.runtime.pluginRegistryFuture,
  runtimeFuture: host.runtime.profileRuntimeFuture,
  controller: host.profiles.profileController,
  onDirtyChanged: host.profiles.onProfileDirtyChanged,
  onEntriesChanged: host.profiles.onProfileEntriesChanged,
  onCreate: host.profiles.onCreateProfile,
);
