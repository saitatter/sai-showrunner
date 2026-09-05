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
  id: 'advss',
  name: 'Advanced Scene Switcher',
  settings: const [
    DartSettingDefinition(id: 'obsConnection', displayName: 'OBS Connection'),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'advss',
      actionId: 'AdvSSMessage',
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
          DartTriggerDefinition(
            pluginId: 'advss',
            triggerId: 'advssEvent',
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
