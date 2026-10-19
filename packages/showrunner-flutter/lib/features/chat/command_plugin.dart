import '../../runtime/expression.dart';
import '../../schema/data_input.dart';
import '../../services/plugin_event_hub.dart';
import '../../plugins/registry/plugin_registry.dart';
import 'command_manager.dart';

DartPluginManifest createChatCommandsPlugin({
  required Future<ChatCommandManager> Function() manager,
  DartPluginEventHub? eventHub,
}) {
  const plugin = PluginId('chatCommands');
  const id = DartDataInputSchema(
    key: 'commandId',
    label: 'Command ID',
    kind: DartDataInputKind.text,
    required: true,
  );
  const user = DartDataInputSchema(
    key: 'userIdentity',
    label: 'User identity (platform:userId, empty for all)',
    kind: DartDataInputKind.text,
  );
  DartDataInputSchema object(String label, List<DartDataInputSchema> fields) =>
      DartDataInputSchema(
        label: label,
        kind: DartDataInputKind.object,
        fields: fields,
      );
  String commandId(RuntimeMap config) {
    final value = config['commandId'];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Command ID is required.');
    }
    return value;
  }

  String? identity(RuntimeMap config) {
    final value = config['userIdentity'] as String?;
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^(twitch|youtube):[^\s:]+$').hasMatch(value)) {
      throw const FormatException('Invalid user identity.');
    }
    return value;
  }

  ActionSpec<RuntimeMap, Object?> action(
    String key,
    String name,
    List<DartDataInputSchema> fields,
    Future<Object?> Function(ChatCommandManager, RuntimeMap) run,
  ) => ActionSpec(
    pluginId: plugin,
    actionId: ActionId(key),
    displayName: name,
    configSchema: object(name, fields),
    invoke: (config, _) async => run(await manager(), config),
  );
  final eventSchema = object('Command event', [
    id,
    const DartDataInputSchema(
      key: 'platform',
      label: 'Platform',
      kind: DartDataInputKind.text,
    ),
    const DartDataInputSchema(
      key: 'viewerId',
      label: 'Viewer ID',
      kind: DartDataInputKind.text,
    ),
    const DartDataInputSchema(
      key: 'message',
      label: 'Message',
      kind: DartDataInputKind.text,
    ),
    const DartDataInputSchema(
      key: 'commandCount',
      label: 'Command count',
      kind: DartDataInputKind.number,
    ),
    const DartDataInputSchema(
      key: 'userCommandCount',
      label: 'User command count',
      kind: DartDataInputKind.number,
    ),
    const DartDataInputSchema(
      key: 'arguments',
      label: 'Arguments',
      kind: DartDataInputKind.array,
    ),
    const DartDataInputSchema(
      key: 'captures',
      label: 'Regex captures',
      kind: DartDataInputKind.object,
    ),
  ]);
  return DartPluginManifest(
    id: plugin,
    name: 'Chat Commands',
    version: '1.0.0',
    actions: [
      action(
        'list',
        'List Chat Commands',
        [
          const DartDataInputSchema(
            key: 'includedOnly',
            label: 'Included commands only',
            kind: DartDataInputKind.boolean,
            defaultValue: true,
          ),
        ],
        (manager, config) async => {
          'commands': manager.commands
              .where((c) => config['includedOnly'] == false || c.includeInList)
              .map((c) => c.toJson())
              .toList(),
        },
      ),
      action('get', 'Get Chat Command and Counters', [id], (
        manager,
        config,
      ) async {
        final key = commandId(config);
        final command = manager.commandById(key);
        return {
          'definition': command.toJson(),
          'counters': manager.countersFor(key).toJson(),
        };
      }),
      action(
        'setEnabled',
        'Enable or Disable Chat Command',
        [
          id,
          const DartDataInputSchema(
            key: 'enabled',
            label: 'Enabled',
            kind: DartDataInputKind.boolean,
            defaultValue: true,
          ),
        ],
        (manager, config) async {
          await manager.setEnabled(
            commandId(config),
            config['enabled'] as bool? ?? true,
          );
          return {'updated': true};
        },
      ),
      action('resetCounters', 'Reset Chat Command Counters', [id], (
        manager,
        config,
      ) async {
        await manager.resetCounters(commandId(config));
        return {'reset': true};
      }),
      action(
        'resetUserCounters',
        'Reset Chat Command User Counters',
        [id, user],
        (manager, config) async {
          await manager.resetUserCounters(
            commandId(config),
            userIdentity: identity(config),
          );
          return {'reset': true};
        },
      ),
      action('resetCooldowns', 'Reset Chat Command Cooldowns', [id, user], (
        manager,
        config,
      ) async {
        await manager.resetCooldowns(
          commandId(config),
          userIdentity: identity(config),
        );
        return {'reset': true};
      }),
      action('delete', 'Delete Chat Command', [id], (manager, config) async {
        await manager.delete(commandId(config));
        return {'deleted': true};
      }),
    ],
    triggers: [
      for (final entry in {
        'triggered': 'Command Triggered',
        'cooldown': 'Command On Cooldown',
        'rejected': 'Command Rejected',
        'failed': 'Command Dispatch Failed',
        'added': 'Command Added',
        'updated': 'Command Updated',
        'deleted': 'Command Deleted',
        'countersReset': 'Command Counters Reset',
        'cooldownReset': 'Command Cooldown Reset',
      }.entries)
        TriggerSpec<RuntimeMap, RuntimeMap>(
          pluginId: plugin,
          triggerId: TriggerId(entry.key),
          displayName: entry.value,
          configSchema: object('Command filter', [
            const DartDataInputSchema(
              key: 'commandId',
              label: 'Command ID (empty for any)',
              kind: DartDataInputKind.text,
            ),
          ]),
          eventSchema: eventSchema,
          listen: () =>
              eventHub?.stream('chatCommands.${entry.key}') ??
              const Stream.empty(),
          matches: (config, event) =>
              config['commandId'] == null ||
              config['commandId'] == '' ||
              config['commandId'] == event['commandId'],
        ),
    ],
  );
}
