import 'dart:io';

import 'package:flutter/material.dart';

import '../../persistence/resource_repository.dart';
import 'resource_editor_registry.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import 'media_picker.dart';

class ResourcesWorkspace extends StatefulWidget {
  const ResourcesWorkspace({
    super.key,
    required this.dataService,
    required this.editorRegistry,
  });

  final ShowRunnerDataService dataService;
  final DartResourceEditorRegistry editorRegistry;

  @override
  State<ResourcesWorkspace> createState() => _ResourcesWorkspaceState();
}

class _ResourcesWorkspaceState extends State<ResourcesWorkspace> {
  Future<Map<String, List<ResourceData>>>? _resourcesFuture;

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

  Future<Map<String, List<ResourceData>>> _loadAll() async {
    final resources = <String, List<ResourceData>>{};
    for (final def in editorRegistry.definitions) {
      resources[def.resourceType] = await ResourceRepository(
        Directory('${dataService.userDirectory.path}/${def.storageDirectory}'),
      ).list();
    }
    return resources;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<ResourceData>>>(
      future: _resourcesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data ?? {};
        final overlays = data['Overlay'] ?? [];
        final variables = data['Variable'] ?? [];

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Resources',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New resource'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage overlays, variables, media items, and persisted smart-device routing.',
            ),
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
                  trailing: _editorLabel('Overlay'),
                );
              }),
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
                  trailing: _editorLabel('Variable'),
                );
              }),
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

  Future<void> _edit(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) async {
    final editor = editorRegistry.find(resourceType);
    if (editor == null) return;
    final directory = Directory(
      '${dataService.userDirectory.path}/${_resourceDirectory(resourceType)}',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => MediaPickerScope(
        directory: Directory('${dataService.userDirectory.path}/media'),
        child: editor.builder(
          context,
          resource,
          (updated) => ResourceRepository(directory).save(updated),
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _create(BuildContext context) async {
    final selection = await showDialog<(String, String)?>(
      context: context,
      builder: (context) => _NewResourceDialog(editorRegistry: editorRegistry),
    );
    if (selection == null || !mounted) return;
    final (resourceType, name) = selection;
    final resource = ResourceData(
      id: 'resource-${DateTime.now().microsecondsSinceEpoch}',
      config: _defaultConfig(resourceType, name),
    );
    await ResourceRepository(
      Directory(
        '${dataService.userDirectory.path}/${_resourceDirectory(resourceType)}',
      ),
    ).save(resource);
    if (mounted) setState(_reload);
  }

  Future<void> _delete(
    BuildContext context,
    ResourceData resource,
    String resourceType,
  ) async {
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
    if (confirmed != true) return;
    await ResourceRepository(
      Directory(
        '${dataService.userDirectory.path}/${_resourceDirectory(resourceType)}',
      ),
    ).delete(resource.id);
    if (mounted) setState(_reload);
  }

  JsonMap _defaultConfig(String resourceType, String name) {
    final def = editorRegistry.find(resourceType);
    if (def != null) return def.defaultConfig(name);
    return {'name': name};
  }

  List<Widget> _buildPluginResources(
    BuildContext context,
    Map<String, List<ResourceData>> data,
  ) {
    final pluginDefs = editorRegistry.definitions.where(
      (def) => def.resourceType != 'Overlay' && def.resourceType != 'Variable',
    );
    return [
      for (final def in pluginDefs)
        _resourceSection(
          context,
          def.resourceType,
          data[def.resourceType] ?? const <ResourceData>[],
        ),
    ];
  }

  Widget _resourceSection(
    BuildContext context,
    String resourceType,
    List<ResourceData> resources,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Text(
        '$resourceType (${resources.length})',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      if (resources.isEmpty)
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: Text('No $resourceType resources defined'),
        )
      else
        ...resources.map(
          (resource) => ListTile(
            onTap: () => _edit(context, resource, resourceType),
            leading: const Icon(Icons.extension),
            title: Text(resource.name),
            subtitle: Text('${resource.config.length} configuration fields'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _editorLabel(resourceType) ?? const SizedBox.shrink(),
                IconButton(
                  tooltip: 'Delete resource',
                  onPressed: () => _delete(context, resource, resourceType),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  String _resourceDirectory(String resourceType) {
    final def = editorRegistry.find(resourceType);
    if (def != null) return def.storageDirectory;
    return resourceType.toLowerCase();
  }
}

class _NewResourceDialog extends StatefulWidget {
  const _NewResourceDialog({required this.editorRegistry});

  final DartResourceEditorRegistry editorRegistry;

  @override
  State<_NewResourceDialog> createState() => _NewResourceDialogState();
}

class _NewResourceDialogState extends State<_NewResourceDialog> {
  final _name = TextEditingController();
  late final List<String> _types;
  late String _type;

  @override
  void initState() {
    super.initState();
    _types = widget.editorRegistry.definitions
        .map((def) => def.resourceType)
        .toList();
    _type = _types.firstOrNull ?? 'Overlay';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New resource'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [
            for (final type in _types)
              DropdownMenuItem(value: type, child: Text(type)),
          ],
          onChanged: (value) => setState(() => _type = value ?? _types.first),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_type, _name.text.trim())),
        child: const Text('Create'),
      ),
    ],
  );
}
