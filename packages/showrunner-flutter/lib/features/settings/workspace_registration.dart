import 'package:flutter/material.dart';

import 'settings_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildSettingsWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => SettingsWorkspace(
  preferences: host.interfacePreferences,
  registryFuture: host.runtime.pluginRegistryFuture,
  dataService: host.runtime.dataService,
);
