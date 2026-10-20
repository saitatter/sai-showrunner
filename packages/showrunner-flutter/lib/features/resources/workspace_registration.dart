import 'package:flutter/material.dart';

import 'resource_editor_registry.dart';
import 'resource_options.dart';
import 'resources_workspace.dart';
import '../support/support_workspaces.dart';
import '../../plugins/variables/runtime.dart';
import '../../app/workspace_registry.dart';

import '../../app/workspace_context.dart';

Widget buildResourcesWorkspace(
  BuildContext context,
  WorkspaceHostContext host,
) => ResourcesWorkspace(
  dataService: host.runtime.dataService,
  editorRegistry: createDefaultResourceEditorRegistry(),
  registryFuture: host.runtime.pluginRegistryFuture,
  streamPlanRuntime: host.runtime.streamPlanRuntime,
  variableRuntime: host.runtime.variableRuntime,
  resourceType: host.navigation.selectedResourceType,
  resourceId: host.navigation.selectedResourceId,
  revision: host.resources.projectCatalogRevision,
  onCreate: host.resources.onCreateResource,
  onOpenResource: host.resources.onOpenResource,
);

Widget? buildResourceDocumentWorkspace(
  BuildContext context,
  WorkspaceId id,
  WorkspaceHostContext host,
) {
  final overlayId = WorkspaceIds.overlayResourceId(id);
  if (overlayId != null) {
    final resource = host.resources.overlayResources[overlayId];
    if (resource == null || host.resources.onSaveOverlay == null) {
      return const LogsWorkspace();
    }
    return OverlayEditorPage(
      resource: resource,
      onSave: host.resources.onSaveOverlay!,
      onDocumentChanged: host.resources.onOverlayDocumentChanged,
      presenceReaderFuture: host.runtime.overlayPresenceReaderFuture,
      obsSourceService: host.runtime.overlayObsSourceService,
      templateSuggestions: [
        for (final definition
            in host.runtime.variableRuntime?.definitions ??
                const <DartVariableDefinition>[]) ...[
          definition.id,
          if (definition.name?.trim().isNotEmpty == true)
            definition.name!.trim(),
        ],
      ],
      onDirtyChanged: (dirty) =>
          host.resources.onOverlayDirtyChanged?.call(resource.id, dirty),
    );
  }

  final streamPlanId = WorkspaceIds.streamPlanResourceId(id);
  if (streamPlanId != null) {
    final resource = host.resources.streamPlanResources[streamPlanId];
    if (resource == null || host.resources.onSaveStreamPlan == null) {
      return const LogsWorkspace();
    }
    return StreamPlanEditorPage(
      resource: resource,
      onSave: host.resources.onSaveStreamPlan!,
      registryFuture: host.runtime.pluginRegistryFuture,
      resourceOptionsLoader: (resourceType) =>
          loadResourceOptions(host.runtime.dataService, resourceType),
      documentMode: true,
      onDocumentChanged: host.resources.onStreamPlanDocumentChanged,
    );
  }

  return null;
}
