import 'dart:io';

import 'package:flutter/material.dart';

import 'support_workspaces.dart';

import '../../app/workspace_context.dart';

Widget buildLogsWorkspace(BuildContext context, WorkspaceHostContext host) =>
    const LogsWorkspace();

Widget buildAboutWorkspace(BuildContext context, WorkspaceHostContext host) =>
    const AboutWorkspace();

Widget buildUpdatesWorkspace(BuildContext context, WorkspaceHostContext host) =>
    UpdateWorkspace(
      updateService: host.support.updateService,
      installService: host.support.installService,
      onRestartRequested: host.support.onRestartRequested,
      downloadDirectory: Directory(
        '${host.runtime.dataService.userDirectory.path}/updates',
      ),
      rollbackDirectory: Directory(
        '${host.runtime.dataService.userDirectory.path}/updates/rollback',
      ),
    );
