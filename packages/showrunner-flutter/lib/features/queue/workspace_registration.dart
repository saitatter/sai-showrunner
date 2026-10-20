import 'package:flutter/material.dart';

import 'queue_workspace.dart';

import '../../app/workspace_context.dart';

Widget buildQueuesWorkspace(BuildContext context, WorkspaceHostContext host) =>
    QueueWorkspace(
      dataService: host.runtime.dataService,
      queue: host.runtime.actionQueue,
      queueManager: host.runtime.queueManager,
    );
