import '../../persistence/persistence_issue.dart';
import '../../persistence/document_revision.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_feedback.dart';
import '../plugins/plugin_metadata.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/dashboards/cloud_sync.dart';
import '../../plugins/stream_plans/manifest.dart';
import '../../plugins/variables/runtime.dart';
import '../../schema/stream_plan.dart';
import 'resource_editor_registry.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import 'media_picker.dart';
import 'resource_options.dart';
import 'new_resource_dialog.dart';

typedef _ResourceWorkspaceCatalog = ({
  Map<String, List<ResourceData>> values,
  List<PersistenceIssue> issues,
});

class ResourcesWorkspace extends StatefulWidget {
  const ResourcesWorkspace({
    super.key,
    required this.dataService,
    required this.editorRegistry,
    this.registryFuture,
    this.streamPlanRuntime,
    this.resourceType,
    this.resourceTypes,
    this.resourceId,
    this.revision = 0,
    this.variableRuntime,
    this.onCreate,
    this.onOpenResource,
  });

  final ShowRunnerDataService dataService;
  final DartResourceEditorRegistry editorRegistry;
  final Future<DartPluginRegistry>? registryFuture;
  final DartStreamPlanRuntime? streamPlanRuntime;
  final String? resourceType;
  final Set<String>? resourceTypes;
  final String? resourceId;
  final int revision;
  final DartVariableRuntime? variableRuntime;
  final FutureOr<void> Function(String resourceType)? onCreate;
  final FutureOr<void> Function(ResourceData resource, String resourceType)?
  onOpenResource;

  @override
  State<ResourcesWorkspace> createState() => _ResourcesWorkspaceState();
}

class _ResourcesWorkspaceState extends State<ResourcesWorkspace> {
  Future<_ResourceWorkspaceCatalog>? _resourcesFuture;
  String? _lastOpenedResourceId;
  Object _resourceOwner = Object();
  bool _busy = false;

  Future<void> _runResourceAction(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    final owner = _resourceOwner;
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (!mounted || !_isCurrent(owner)) return;
      showShowRunnerFeedback(
        context,
        'Resource operation failed. Check storage and the configuration, then retry.',
        severity: ShowRunnerFeedbackSeverity.error,
      );
    } finally {
      if (_isCurrent(owner)) setState(() => _busy = false);
    }
  }

  bool _isCurrent(Object owner) => mounted && identical(owner, _resourceOwner);

  ShowRunnerDataService get dataService => widget.dataService;
  DartResourceEditorRegistry get editorRegistry => widget.editorRegistry;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _resourcesFuture = _loadAll();
  }

  @override
  void didUpdateWidget(covariant ResourcesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        !identical(oldWidget.dataService, widget.dataService) ||
        !identical(oldWidget.editorRegistry, widget.editorRegistry) ||
        oldWidget.registryFuture != widget.registryFuture;
    if (sourceChanged ||
        oldWidget.resourceType != widget.resourceType ||
        oldWidget.resourceId != widget.resourceId) {
      _resourceOwner = Object();
      _busy = false;
      _lastOpenedResourceId = null;
    }
    if (sourceChanged || oldWidget.revision != widget.revision) _reload();
  }

  Future<_ResourceWorkspaceCatalog> _loadAll() async {
    final data = dataService;
    final editors = editorRegistry;
    final resources = <String, List<ResourceData>>{};
    final issues = <PersistenceIssue>[];
    for (final def in editors.definitions) {
      try {
        final entries = await data.storage
            .resource(def.resourceTypeId)
            .listWithErrors();
        resources[def.resourceType] = [
          for (final entry in entries)
            if (entry.resource != null && entry.error == null) entry.resource!,
        ];
        for (final entry in entries) {
          if (entry.error != null) {
            issues.add(
              PersistenceIssue.fromError(
                entry.error!,
                owner: def.resourceType,
                document: entry.fileName,
              ),
            );
          }
        }
      } catch (error) {
        issues.add(
          PersistenceIssue.fromError(
            error,
            owner: def.resourceType,
            document: def.storageDirectory,
          ),
        );
      }
    }
    return (values: resources, issues: issues);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResourceWorkspaceCatalog>(
      future: _resourcesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Resource catalog could not be read. Check storage access and retry.',
            ),
          );
        }
        final data = snapshot.data?.values ?? {};
        final issues = snapshot.data?.issues ?? const <PersistenceIssue>[];
        final overlays = data['Overlay'] ?? [];
        final variables = data['Variable'] ?? [];
        final focusedType = widget.resourceType;
        final focusedDefinition = focusedType == null
            ? null
            : editorRegistry.find(focusedType);
        final resourceId = widget.resourceId;
        if (focusedType != null && resourceId != null) {
          final resource = data[focusedType]
              ?.where((candidate) => candidate.id == resourceId)
              .firstOrNull;
          if (resource != null && resourceId != _lastOpenedResourceId) {
            _lastOpenedResourceId = resourceId;
            final owner = _resourceOwner;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_isCurrent(owner)) {
                unawaited(_edit(context, resource, focusedType));
              }
            });
          }
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (focusedDefinition != null) ...[
                  Icon(
                    pluginIconFor(focusedDefinition.pluginId),
                    color: pluginColorFor(focusedDefinition.pluginId),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        focusedDefinition?.displayName ??
                            (focusedType ?? 'Resources'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (focusedType != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_descriptionFor(focusedType)),
                        ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      widget.resourceType == null || widget.onCreate == null
                      ? () => _create(context)
                      : () => widget.onCreate!.call(widget.resourceType!),
                  icon: const Icon(Icons.add),
                  label: const Text('New resource'),
                ),
              ],
            ),
            for (final issue in issues.where(
              (issue) => focusedType == null || issue.owner == focusedType,
            ))
              ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text('${issue.owner} / ${issue.document}'),
                subtitle: Text(issue.message),
              ),
            const SizedBox(height: 8),
            if (focusedType == null && widget.resourceTypes == null)
              const Text(
                'Manage overlays, variables, stream plans, and persisted smart-device routing.',
              ),
            if (focusedType == 'Overlay' ||
                (focusedType == null &&
                    (widget.resourceTypes == null ||
                        widget.resourceTypes!.contains('Overlay')))) ...[
              const SizedBox(height: 20),
              Text(
                'Overlays (${overlays.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (overlays.isEmpty)
                const ListTile(
                  leading: Icon(Icons.layers_clear),
                  title: Text('No overlays defined'),
                )
              else
                ...overlays.map((resource) {
                  final overlay = OverlayResource.fromResource(resource);
                  return ListTile(
                    onTap: () => _edit(context, resource, 'Overlay'),
                    leading: const Icon(Icons.layers),
                    title: Text(overlay.name),
                    subtitle: Text(
                      '${overlay.width}x${overlay.height} · ${overlay.widgets.length} widgets',
                    ),
                    trailing: _deleteButton(context, resource, 'Overlay'),
                  );
                }),
            ],
            if (focusedType == 'Variable' ||
                (focusedType == null &&
                    (widget.resourceTypes == null ||
                        widget.resourceTypes!.contains('Variable')))) ...[
              const SizedBox(height: 20),
              Text(
                'Variables (${variables.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (variables.isEmpty)
                const ListTile(
                  leading: Icon(Icons.data_object),
                  title: Text('No variables defined'),
                )
              else
                ...variables.map((resource) {
                  final variable = VariableResource.fromResource(resource);
                  return ListTile(
                    onTap: () => _edit(context, resource, 'Variable'),
                    leading: const Icon(Icons.tune),
                    title: Text(variable.name),
                    subtitle: Text(
                      'Type: ${variable.type} · Default: ${variable.defaultValue ?? 'null'} · Current: ${variable.currentValue ?? 'null'}',
                    ),
                    trailing: _deleteButton(context, resource, 'Variable'),
                  );
                }),
            ],
            ..._buildPluginResources(context, data),
          ],
        );
      },
    );
  }

  Widget? _editorLabel(String resourceType) {
    final editor = editorRegistry.find(resourceType);
    return editor == null
        ? null
        : Tooltip(
            message: '${editor.displayName} editor available',
            child: const Icon(Icons.edit_outlined),
          );
  }

  Widget _deleteButton(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _editorLabel(resourceType) ?? const SizedBox.shrink(),
      IconButton(
        tooltip: 'Delete resource',
        onPressed: () => _delete(context, resource, resourceType),
        icon: const Icon(Icons.delete_outline),
      ),
    ],
  );

  Future<void> _edit(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) => _runResourceAction(() => _editCurrent(context, resource, resourceType));

  Future<void> _editCurrent(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) async {
    final owner = _resourceOwner;
    final data = dataService;
    final editors = editorRegistry;
    final registryFuture = widget.registryFuture;
    final variableRuntime = widget.variableRuntime;
    final planRuntime = widget.streamPlanRuntime;
    final onOpenResource = widget.onOpenResource;
    final repository = data.storage.resource(ResourceTypeId(resourceType));
    final editor = editors.find(resourceType);
    final registry = await registryFuture;
    if (!_isCurrent(owner) || !context.mounted) return;
    final enabled =
        registry == null ||
        (editor != null &&
            registry.manifest(editor.ownerId) != null &&
            registry.isPluginEnabledId(editor.ownerId));
    if (editor == null ||
        editor.readOnlyReason(resource, enabled: enabled) != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => editors.build(
          ResourceTypeId(resourceType),
          context,
          resource,
          (_) async {},
          enabled: enabled,
        ),
      );
      return;
    }
    if ((resourceType == 'Overlay' || resourceType == 'StreamPlan') &&
        onOpenResource != null) {
      await onOpenResource.call(resource, resourceType);
      return;
    }
    if (resourceType == 'Overlay') return;
    var storageRevision = DocumentRevision.of(resource.toJson());
    await showDialog<void>(
      context: context,
      builder: (context) {
        Future<void> save(ResourceData updated) async {
          if (!_isCurrent(owner)) {
            throw StateError('The resource editor is no longer current.');
          }
          if (registry != null && !registry.isPluginEnabledId(editor.ownerId)) {
            throw StateError('The owning plugin is disabled.');
          }
          await repository.save(updated, expectedRevision: storageRevision);
          storageRevision = DocumentRevision.of(updated.toJson());
          if (!_isCurrent(owner)) return;
          if (resourceType == 'Dashboard') {
            final synchronized = await DashboardCloudSyncService(
              dataService: data,
            ).synchronize(updated);
            await repository.save(
              synchronized,
              expectedRevision: storageRevision,
            );
            storageRevision = DocumentRevision.of(synchronized.toJson());
          }
          if (resourceType == 'Variable') {
            await variableRuntime?.reload();
          }
          final streamPlanRuntime = planRuntime;
          if (resourceType == 'StreamPlan' &&
              streamPlanRuntime?.activePlanId == updated.id) {
            await streamPlanRuntime!.updateActivePlan(
              updated.id,
              StreamPlanData.fromConfig(updated.config),
            );
          }
        }

        final content = editor.build(
          context,
          resource,
          save,
          registryFuture: registryFuture,
          resourceOptionsLoader: (type) => loadResourceOptions(data, type),
        );
        return MediaPickerScope(
          directory: Directory('${data.userDirectory.path}/media'),
          child: content,
        );
      },
    );
    if (_isCurrent(owner)) setState(_reload);
  }

  Future<void> _create(BuildContext context) =>
      _runResourceAction(() => _createCurrent(context));

  Future<void> _createCurrent(BuildContext context) async {
    final owner = _resourceOwner;
    final data = dataService;
    final editors = editorRegistry;
    final variableRuntime = widget.variableRuntime;
    final selection = await showDialog<(String, String)?>(
      context: context,
      builder: (context) => NewResourceDialog(
        editorRegistry: editors,
        resourceType: widget.resourceType,
        resourceTypes: widget.resourceTypes,
      ),
    );
    if (selection == null || !_isCurrent(owner)) return;
    final (resourceType, name) = selection;
    final resource = ResourceData(
      id: 'resource-${DateTime.now().microsecondsSinceEpoch}',
      config: editors.find(resourceType)?.defaultConfig(name) ?? {'name': name},
    );
    await data.storage
        .resource(ResourceTypeId(resourceType))
        .save(resource, requireAbsent: true);
    if (!_isCurrent(owner)) return;
    if (resourceType == 'Variable') {
      await variableRuntime?.reload();
    }
    if (_isCurrent(owner)) setState(_reload);
  }

  Future<void> _delete(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) =>
      _runResourceAction(() => _deleteCurrent(context, resource, resourceType));

  Future<void> _deleteCurrent(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) async {
    final owner = _resourceOwner;
    final data = dataService;
    final repository = data.storage.resource(ResourceTypeId(resourceType));
    final variableRuntime = widget.variableRuntime;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete resource?'),
        content: Text('Delete ${resource.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrent(owner)) return;
    if (resourceType == 'Dashboard') {
      // Remove the public share before the local dashboard file. Keep the
      // ordering so a failed cloud request never leaves an orphaned share.
      await DashboardCloudSyncService(dataService: data).synchronize(
        ResourceData(
          id: resource.id,
          config: {...resource.config, 'remoteTwitchIds': const <String>[]},
          state: resource.state,
        ),
      );
    }
    await repository.delete(
      resource.id,
      expectedRevision: DocumentRevision.of(resource.toJson()),
    );
    if (!_isCurrent(owner)) return;
    if (resourceType == 'Variable') {
      await variableRuntime?.reload();
    }
    if (_isCurrent(owner)) setState(_reload);
  }

  List<Widget> _buildPluginResources(
    BuildContext context,
    Map<String, List<ResourceData>> data,
  ) {
    final pluginDefs = editorRegistry.definitions.where((def) {
      if (def.resourceType == 'Overlay' || def.resourceType == 'Variable') {
        return false;
      }
      if (widget.resourceTypes != null &&
          !widget.resourceTypes!.contains(def.resourceType)) {
        return false;
      }
      return widget.resourceType == null ||
          widget.resourceType == def.resourceType;
    });
    return [
      for (final def in pluginDefs)
        _resourceSection(
          context,
          def.resourceType,
          data[def.resourceType] ?? const <ResourceData>[],
          showTitle: widget.resourceType == null,
        ),
    ];
  }

  Widget _resourceSection(
    BuildContext context,
    String resourceType,
    List<ResourceData> resources, {
    bool showTitle = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      if (showTitle)
        Text(
          '$resourceType (${resources.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      if (showTitle) const SizedBox(height: 8),
      if (resources.isEmpty)
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: Text('No $resourceType resources defined'),
        )
      else
        ...resources.map(
          (resource) => _resourceTile(context, resource, resourceType),
        ),
    ],
  );

  Widget _resourceTile(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) {
    final runtime = resourceType == 'StreamPlan'
        ? widget.streamPlanRuntime
        : null;
    Widget tile() => ListTile(
      onTap: () => _edit(context, resource, resourceType),
      leading: Icon(runtime == null ? Icons.extension : Icons.play_circle),
      title: Text(resource.name),
      subtitle: runtime == null
          ? Text('${resource.config.length} configuration fields')
          : _streamPlanSubtitle(resource, runtime),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (runtime != null) _streamPlanControls(context, resource, runtime),
          _editorLabel(resourceType) ?? const SizedBox.shrink(),
          IconButton(
            tooltip: 'Delete resource',
            onPressed: () => _delete(context, resource, resourceType),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
    return runtime == null
        ? tile()
        : AnimatedBuilder(animation: runtime, builder: (_, _) => tile());
  }

  Widget _streamPlanSubtitle(
    ResourceData resource,
    DartStreamPlanRuntime runtime,
  ) {
    final plan = StreamPlanData.fromConfig(resource.config);
    final isActive = runtime.activePlanId == resource.id;
    final activeSegment = isActive ? runtime.activeSegmentId : null;
    return Text(
      isActive
          ? 'Active${activeSegment == null ? '' : ' · Segment $activeSegment'} · ${plan.segments.length} segments'
          : '${plan.segments.length} segments',
    );
  }

  Widget _streamPlanControls(
    BuildContext context,
    ResourceData resource,
    DartStreamPlanRuntime runtime,
  ) => AnimatedBuilder(
    animation: runtime,
    builder: (context, child) {
      final active = runtime.activePlanId == resource.id;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous segment',
            onPressed: active
                ? () => _runStreamPlanAction(
                    context,
                    (registry) async => runtime.transitionToPreviousSegment(
                      resource.id,
                      StreamPlanData.fromConfig(resource.config),
                      registry: registry,
                    ),
                  )
                : null,
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            tooltip: active ? 'Deactivate stream plan' : 'Activate stream plan',
            onPressed: () => active
                ? _runStreamPlanAction(
                    context,
                    (registry) async =>
                        runtime.deactivatePlan(registry: registry),
                  )
                : _runStreamPlanAction(
                    context,
                    (registry) async => runtime.activatePlan(
                      resource.id,
                      StreamPlanData.fromConfig(resource.config),
                      registry: registry,
                    ),
                  ),
            icon: Icon(active ? Icons.stop_circle : Icons.play_circle),
          ),
          IconButton(
            tooltip: 'Next segment',
            onPressed: active
                ? () => _runStreamPlanAction(
                    context,
                    (registry) async => runtime.transitionToNextSegment(
                      resource.id,
                      StreamPlanData.fromConfig(resource.config),
                      registry: registry,
                    ),
                  )
                : null,
            icon: const Icon(Icons.skip_next),
          ),
        ],
      );
    },
  );

  Future<void> _runStreamPlanAction(
    BuildContext context,
    Future<Object?> Function(DartPluginRegistry registry) action,
  ) async {
    final owner = _resourceOwner;
    final registryFuture = widget.registryFuture;
    if (registryFuture == null) return;
    try {
      final registry = await registryFuture;
      if (!_isCurrent(owner)) return;
      await action(registry);
    } on Object {
      if (!_isCurrent(owner) || !context.mounted) return;
      showShowRunnerFeedback(
        context,
        'Stream Plan action failed. Check the connection and retry.',
        severity: ShowRunnerFeedbackSeverity.error,
      );
    }
  }

  String _descriptionFor(String resourceType) => switch (resourceType) {
    'OBSConnection' =>
      'Manage the OBS websocket connections used by actions, overlays, and stream automation.',
    'TwitchAccount' =>
      'Manage Twitch accounts used by chat, channel points, and stream automation.',
    'CustomTwitchViewerGroup' =>
      'Manage reusable Twitch viewer groups for automation conditions.',
    'ChannelPointReward' =>
      'Manage Twitch channel point rewards and their automation behavior.',
    'StreamPlan' => 'Manage stream plans and their activation segments.',
    'Overlay' => 'Manage browser-source overlays and their widgets.',
    'Variable' => 'Manage persistent variables used by automations.',
    _ => 'Manage persisted $resourceType resources used by ShowRunner.',
  };
}
