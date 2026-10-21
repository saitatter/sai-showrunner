import '../plugins/registry/builtin_resource_specs.dart';
import '../plugins/registry/plugin_contract.dart';
import 'secret_settings_store.dart';

/// These describe stored bytes, not runtime/plugin instances or secret values.
enum PersistenceAuthority { authoring, durableRuntime, encryptedSecrets }

enum PersistenceFormat { json, yaml, jsonOrYaml, dpapiYaml }

enum PersistenceWriteScope { singleFile, resourceGroup, settingsGroup }

enum PersistenceCodec {
  automationV1,
  resourceEnvelope,
  runtimeMap,
  profile,
  queueConfig,
  queueState,
  viewerDefinitions,
  viewerRow,
  settings,
  chatV1,
  windowState,
  encryptedYaml,
}

final class PersistedDocumentContract {
  const PersistedDocumentContract({
    required this.id,
    required this.owner,
    required this.pathPattern,
    required this.format,
    required this.codec,
    required this.authority,
    this.writeScope = PersistenceWriteScope.singleFile,
    this.resourceType,
    this.secretFields = const {},
    this.runtimeOnlyFields = const {},
  });
  final String id;
  final PluginId owner;
  final String pathPattern;
  final PersistenceFormat format;
  final PersistenceCodec codec;
  final PersistenceAuthority authority;

  /// Required coherence boundary; per-file atomic rename alone is insufficient
  /// for group writes. The architecture document records implementation gaps.
  final PersistenceWriteScope writeScope;
  final ResourceTypeId? resourceType;
  final Set<String> secretFields;
  final Set<String> runtimeOnlyFields;
}

final List<PersistedDocumentContract> persistedDocumentContracts =
    List.unmodifiable([
      const PersistedDocumentContract(
        id: 'automations',
        owner: PluginId('ShowRunner'),
        pathPattern: 'automations/{file}.yaml',
        format: PersistenceFormat.jsonOrYaml,
        codec: PersistenceCodec.automationV1,
        authority: PersistenceAuthority.authoring,
        runtimeOnlyFields: {'trace', 'selection', 'camera', 'executionContext'},
      ),
      const PersistedDocumentContract(
        id: 'profiles',
        owner: PluginId('ShowRunner'),
        pathPattern: 'profiles/{file}.yaml',
        format: PersistenceFormat.jsonOrYaml,
        codec: PersistenceCodec.profile,
        authority: PersistenceAuthority.authoring,
        runtimeOnlyFields: {'subscriptions', 'activeSession', 'cancellation'},
      ),
      const PersistedDocumentContract(
        id: 'queue-config',
        owner: PluginId('ShowRunner'),
        pathPattern: 'queues/{file}.yaml',
        format: PersistenceFormat.yaml,
        codec: PersistenceCodec.queueConfig,
        authority: PersistenceAuthority.authoring,
      ),
      // QueueRepository is an explicitly supplied file adapter; the application
      // currently does not bind a fixed queue-history path at host composition.
      const PersistedDocumentContract(
        id: 'queue-history',
        owner: PluginId('ShowRunner'),
        pathPattern: '{explicit QueueRepository file}',
        format: PersistenceFormat.json,
        codec: PersistenceCodec.queueState,
        authority: PersistenceAuthority.durableRuntime,
        runtimeOnlyFields: {'cancellationToken', 'runningFuture'},
      ),
      for (final resource in builtInResourceSpecs)
        PersistedDocumentContract(
          id: 'resource:${resource.resourceTypeId.value}',
          owner: resource.ownerId,
          pathPattern: '${resource.storageDirectory}/{id}.{json|yaml}',
          format: PersistenceFormat.jsonOrYaml,
          codec: PersistenceCodec.resourceEnvelope,
          authority: PersistenceAuthority.authoring,
          resourceType: resource.resourceTypeId,
          writeScope: PersistenceWriteScope.resourceGroup,
          secretFields: Set.unmodifiable(
            secretResourceFieldIdsFor(resource.resourceTypeId.value),
          ),
        ),
      const PersistedDocumentContract(
        id: 'resource-state',
        owner: PluginId('ShowRunner'),
        pathPattern: '{resource directory}/.state/{id}.json',
        format: PersistenceFormat.json,
        codec: PersistenceCodec.runtimeMap,
        authority: PersistenceAuthority.durableRuntime,
        writeScope: PersistenceWriteScope.resourceGroup,
      ),
      const PersistedDocumentContract(
        id: 'resource-secrets',
        owner: PluginId('ShowRunner'),
        pathPattern: 'secrets/resources/{type}/{id}.yaml',
        format: PersistenceFormat.dpapiYaml,
        codec: PersistenceCodec.encryptedYaml,
        authority: PersistenceAuthority.encryptedSecrets,
        writeScope: PersistenceWriteScope.resourceGroup,
      ),
      const PersistedDocumentContract(
        id: 'plugin-settings',
        owner: PluginId('ShowRunner'),
        pathPattern: 'settings/{plugin}.yaml',
        format: PersistenceFormat.yaml,
        codec: PersistenceCodec.settings,
        authority: PersistenceAuthority.authoring,
        writeScope: PersistenceWriteScope.settingsGroup,
      ),
      const PersistedDocumentContract(
        id: 'plugin-secrets',
        owner: PluginId('ShowRunner'),
        pathPattern: 'secrets/{plugin}.yaml',
        format: PersistenceFormat.dpapiYaml,
        codec: PersistenceCodec.encryptedYaml,
        authority: PersistenceAuthority.encryptedSecrets,
        writeScope: PersistenceWriteScope.settingsGroup,
      ),
      const PersistedDocumentContract(
        id: 'chat-preferences',
        owner: PluginId('ShowRunner'),
        pathPattern: 'settings/chat.yaml',
        format: PersistenceFormat.yaml,
        codec: PersistenceCodec.chatV1,
        authority: PersistenceAuthority.authoring,
      ),
      const PersistedDocumentContract(
        id: 'chat-actions',
        owner: PluginId('ShowRunner'),
        pathPattern: 'settings/chat-actions.yaml',
        format: PersistenceFormat.yaml,
        codec: PersistenceCodec.chatV1,
        authority: PersistenceAuthority.authoring,
      ),
      const PersistedDocumentContract(
        id: 'chat-commands',
        owner: PluginId('chatCommands'),
        pathPattern: 'chat-commands.json',
        format: PersistenceFormat.json,
        codec: PersistenceCodec.chatV1,
        authority: PersistenceAuthority.authoring,
        runtimeOnlyFields: {'inFlightDispatch', 'cooldownTimers'},
      ),
      const PersistedDocumentContract(
        id: 'command-counters',
        owner: PluginId('chatCommands'),
        pathPattern: 'state/chat-command-counters.json',
        format: PersistenceFormat.json,
        codec: PersistenceCodec.chatV1,
        authority: PersistenceAuthority.durableRuntime,
      ),
      const PersistedDocumentContract(
        id: 'viewer-definitions',
        owner: PluginId('ShowRunner'),
        pathPattern: 'viewer-data/variables.yaml',
        format: PersistenceFormat.yaml,
        codec: PersistenceCodec.viewerDefinitions,
        authority: PersistenceAuthority.authoring,
      ),
      const PersistedDocumentContract(
        id: 'viewer-rows',
        owner: PluginId('ShowRunner'),
        pathPattern: 'viewer-data/{provider}/{base64url(id)}.json',
        format: PersistenceFormat.json,
        codec: PersistenceCodec.viewerRow,
        authority: PersistenceAuthority.durableRuntime,
      ),
      const PersistedDocumentContract(
        id: 'workspace-navigation',
        owner: PluginId('ShowRunner'),
        pathPattern: 'settings/showrunner-flutter.yaml',
        format: PersistenceFormat.yaml,
        codec: PersistenceCodec.settings,
        authority: PersistenceAuthority.durableRuntime,
      ),
      const PersistedDocumentContract(
        id: 'window-state',
        owner: PluginId('ShowRunner'),
        pathPattern: 'state/window.json',
        format: PersistenceFormat.json,
        codec: PersistenceCodec.windowState,
        authority: PersistenceAuthority.durableRuntime,
      ),
    ]);

PersistedDocumentContract pluginSettingsContract(PluginId plugin) =>
    PersistedDocumentContract(
      id: 'settings:${plugin.value}',
      owner: plugin,
      pathPattern: 'settings/${plugin.value}.yaml',
      format: PersistenceFormat.yaml,
      codec: PersistenceCodec.settings,
      authority: PersistenceAuthority.authoring,
      writeScope: PersistenceWriteScope.settingsGroup,
      secretFields: Set.unmodifiable(secretSettingIdsFor(plugin.value)),
    );
