import '../../schema/resource_codec.dart';
import '../../runtime/expression.dart';
import 'package:flutter/material.dart';
import '../../components/data_inputs/resource_schema.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/resource.dart';
import '../../schema/json.dart';

typedef DartResourceEditorBuilder =
    Widget Function(
      BuildContext context,
      ResourceData resource,
      Future<void> Function(ResourceData resource) onSave,
    );

typedef DartResourceEditorRuntimeBuilder =
    Widget Function(
      BuildContext context,
      ResourceData resource,
      Future<void> Function(ResourceData resource) onSave, {
      required Future<DartPluginRegistry> registryFuture,
      required ResourceOptionsLoader resourceOptionsLoader,
    });

final class ResourceEditorContribution implements DartResourceContract {
  ResourceEditorContribution.fromContract({
    required DartResourceContract contract,
    required this.builder,
    this.runtimeBuilder,
    this.validate,
    this.readOnlyBuilder,
    this.capabilities = const ResourceEditorCapabilities(),
  }) : pluginId = contract.ownerId.value,
       resourceType = contract.resourceTypeId.value,
       displayName = contract.displayName,
       storageDirectory = contract.storageDirectory,
       defaultConfig = contract.createDefaultConfig,
       configurationCodec = contract.configurationCodec;

  final String pluginId;
  final String resourceType;
  @override
  final String displayName;
  @override
  final String storageDirectory;
  final JsonMap Function(String name) defaultConfig;
  @override
  final ResourceConfigurationCodec configurationCodec;
  final DartResourceEditorBuilder builder;
  final DartResourceEditorRuntimeBuilder? runtimeBuilder;
  final String? Function(ResourceData resource)? validate;
  final Widget Function(
    BuildContext context,
    ResourceData resource,
    String reason,
  )?
  readOnlyBuilder;
  final ResourceEditorCapabilities capabilities;

  Widget build(
    BuildContext context,
    ResourceData resource,
    Future<void> Function(ResourceData) onSave, {
    bool enabled = true,
    Future<DartPluginRegistry>? registryFuture,
    ResourceOptionsLoader? resourceOptionsLoader,
  }) {
    final reason = readOnlyReason(resource, enabled: enabled);
    if (reason != null || !capabilities.canSave) {
      final message = reason ?? 'This resource is read-only.';
      return readOnlyBuilder?.call(context, resource, message) ??
          ResourceReadOnlyInspector(
            resource: resource,
            resourceType: resourceTypeId,
            reason: message,
          );
    }
    final runtime = runtimeBuilder;
    if (runtime != null &&
        registryFuture != null &&
        resourceOptionsLoader != null) {
      return runtime(
        context,
        resource,
        onSave,
        registryFuture: registryFuture,
        resourceOptionsLoader: resourceOptionsLoader,
      );
    }
    return builder(context, resource, onSave);
  }

  String? readOnlyReason(ResourceData resource, {bool enabled = true}) {
    if (!enabled) return 'The owning plugin is disabled.';
    if (!capabilities.canSave) return 'This resource is read-only.';
    try {
      configurationCodec.validate(resource.config);
      return validate?.call(resource);
    } catch (_) {
      return 'The resource configuration is unsupported or malformed.';
    }
  }

  @override
  PluginId get ownerId => PluginId(pluginId);

  @override
  ResourceTypeId get resourceTypeId => ResourceTypeId(resourceType);

  @override
  RuntimeMap createDefaultConfig(String name) => defaultConfig(name);

  ResourceTypeId get key => resourceTypeId;
}

final class DartResourceEditorRegistry {
  final _editors = <ResourceTypeId, ResourceEditorContribution>{};

  void register(ResourceEditorContribution definition) {
    if (definition.pluginId.isEmpty) {
      throw ArgumentError.value(definition.pluginId, 'definition.pluginId');
    }
    if (definition.resourceType.isEmpty) {
      throw ArgumentError.value(
        definition.resourceType,
        'definition.resourceType',
      );
    }
    if (_editors.containsKey(definition.key)) {
      throw ArgumentError(
        'Resource editor is registered more than once: ${definition.resourceType}',
      );
    }
    _editors[definition.key] = definition;
  }

  Widget build(
    ResourceTypeId type,
    BuildContext context,
    ResourceData resource,
    Future<void> Function(ResourceData) onSave, {
    bool enabled = true,
  }) {
    final contribution = _editors[type];
    return contribution?.build(context, resource, onSave, enabled: enabled) ??
        ResourceReadOnlyInspector(
          resource: resource,
          resourceType: type,
          reason:
              'No editor contribution is registered for this resource type.',
        );
  }

  ResourceEditorContribution? find(String resourceType) =>
      _editors[ResourceTypeId(resourceType)];

  Iterable<ResourceEditorContribution> get definitions =>
      List.unmodifiable(_editors.values);
}

/// Authoring capabilities belong to Flutter UI contributions, never codecs.
final class ResourceEditorCapabilities {
  const ResourceEditorCapabilities({
    this.canSave = true,
    this.tracksDirty = false,
    this.supportsUndo = false,
  });
  final bool canSave;
  final bool tracksDirty;
  final bool supportsUndo;
}

/// Deliberately excludes config values: loaded resources may contain secrets.
class ResourceReadOnlyInspector extends StatelessWidget {
  const ResourceReadOnlyInspector({
    super.key,
    required this.resource,
    required this.resourceType,
    required this.reason,
  });
  final ResourceData resource;
  final ResourceTypeId resourceType;
  final String reason;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Resource cannot be edited'),
    content: Text(
      '$resourceType / ${resource.id}\n$reason\nThe stored document has not been changed.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
