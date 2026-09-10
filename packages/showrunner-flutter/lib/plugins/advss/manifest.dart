import '../../schema/data_input.dart';
import '../../services/plugin_event_hub.dart';
import '../obs/actions.dart';
import '../registry/plugin_contract.dart';

const _vendorName = 'AdvancedSceneSwitcher';

const _messageSchema = DartDataInputSchema(
  label: 'Advanced Scene Switcher message',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
  ],
);

const _eventSchema = DartDataInputSchema(
  label: 'Advanced Scene Switcher event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

DartPluginManifest createAdvssPlugin(
  ObsTransport transport, {
  DartPluginEventHub? eventHub,
}) => DartPluginManifest(
  id: PluginId('advss'),
  name: 'Advanced Scene Switcher',
  settings: const [
    SettingSpec(id: SettingId('obsConnection'), displayName: 'OBS Connection'),
  ],
  actions: [
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('advss'),
      actionId: ActionId('AdvSSMessage'),
      displayName: 'Advanced Scene Switcher Message',
      configSchema: _messageSchema,
      invoke: (config, context) => transport.call('CallVendorRequest', {
        'vendorName': _vendorName,
        'requestType': 'AdvancedSceneSwitcherMessage',
        'requestData': {'message': config['message']?.toString() ?? ''},
      }),
    ),
  ],
  triggers: eventHub == null
      ? const []
      : [
          TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
            pluginId: PluginId('advss'),
            triggerId: TriggerId('advssEvent'),
            displayName: 'Advanced Scene Switcher Event',
            configSchema: _eventSchema,
            listen: () => eventHub.stream('obsVendorEvent'),
            matches: (config, payload) =>
                payload['vendorName'] == _vendorName &&
                payload['eventType'] == 'AdvancedSceneSwitcherEvent' &&
                (config['message']?.toString().trim().isEmpty != false ||
                    config['message']?.toString() ==
                        payload['message']?.toString()),
          ),
        ],
);
