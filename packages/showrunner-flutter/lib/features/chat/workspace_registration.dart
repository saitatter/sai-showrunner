import 'chat_workspace.dart';
import 'commands_workspace.dart';

import 'package:flutter/material.dart';

import '../../app/workspace_context.dart';

Widget buildChatWorkspace(BuildContext context, WorkspaceHostContext host) =>
    host.runtime.chatRuntime == null
    ? const SizedBox.shrink()
    : ChatWorkspace(
        runtime: host.runtime.chatRuntime!,
        providerEvents: host.runtime.providerEvents,
        dock: host.runtime.chatDock,
      );

Widget buildChatCommandsWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => host.runtime.chatRuntime == null
    ? const SizedBox.shrink()
    : CommandsWorkspace(
        manager: host.runtime.chatRuntime!.commands,
        dataService: host.runtime.dataService,
      );
