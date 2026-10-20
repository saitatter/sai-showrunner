import 'package:flutter/material.dart';

import 'remote_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildRemoteWorkspace(BuildContext context, WorkspaceHostContext host) =>
    RemoteWorkspace(
      dataService: host.runtime.dataService,
      registryFuture: host.runtime.pluginRegistryFuture,
    );
