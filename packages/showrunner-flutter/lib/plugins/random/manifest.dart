import 'dart:math';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../overlays/manifest.dart';
import '../registry/plugin_contract.dart';

const _randomSchema = DartDataInputSchema(
  label: 'Random range',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Minimum',
      key: 'min',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0,
    ),
    DartDataInputSchema(
      label: 'Maximum',
      key: 'max',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 100,
    ),
  ],
);

const _spinWheelSchema = DartDataInputSchema(
  label: 'Spin wheel',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Wheel',
      key: 'wheel',
      kind: DartDataInputKind.object,
      required: true,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Strength',
      key: 'strength',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 1,
    ),
  ],
);

DartPluginManifest createRandomPlugin({DartPluginEventHub? eventHub}) =>
    DartPluginManifest(
      id: 'random',
      name: 'Random',
      actions: [
        DartActionDefinition(
          pluginId: 'random',
          actionId: 'random',
          displayName: 'Random Decision',
          invoke: _random,
          configSchema: _randomSchema,
        ),
        DartActionDefinition(
          pluginId: 'random',
          actionId: 'spinWheel',
          displayName: 'Spin Wheel',
          invoke: (config, context) => _spinWheel(eventHub, config, context),
          configSchema: _spinWheelSchema,
        ),
      ],
      triggers: eventHub == null
          ? const []
          : [
              DartTriggerDefinition(
                pluginId: 'random',
                triggerId: 'wheelLanded',
                displayName: 'Wheel Stopped',
                configSchema: _wheelTriggerSchema,
                listen: () => _wheelEvents(eventHub),
                matches: _matchesWheel,
              ),
            ],
    );

const _wheelTriggerSchema = DartDataInputSchema(
  label: 'Wheel trigger',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Wheel',
      key: 'wheel',
      kind: DartDataInputKind.object,
      required: true,
      fields: [
        DartDataInputSchema(
          label: 'Widget ID',
          key: 'widgetId',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Overlay ID',
          key: 'overlayId',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Item name',
      key: 'item',
      kind: DartDataInputKind.text,
    ),
  ],
);

final _randomGenerator = Random();

Future<Object?> _random(RuntimeMap config, EvaluationContext context) async {
  final minVal = (config['min'] as num?)?.toDouble() ?? 0.0;
  final maxVal = (config['max'] as num?)?.toDouble() ?? 100.0;
  final value = minVal + _randomGenerator.nextDouble() * (maxVal - minVal);
  return {'value': value};
}

Future<Object?> _spinWheel(
  DartPluginEventHub? eventHub,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final strength = (config['strength'] as num?)?.toDouble() ?? 1.0;
  final wheel = config['wheel'];
  if (eventHub != null && wheel is Map) {
    eventHub.emit(OverlayEventIds.widgetRpc, {
      'overlayId': wheel['overlayId'],
      'widgetId': wheel['widgetId'],
      'rpcId': 'spinWheel',
      'args': [strength],
    });
  }
  return {'spun': true, 'strength': strength};
}

Stream<RuntimeMap> _wheelEvents(DartPluginEventHub eventHub) => eventHub
    .stream(OverlayEventIds.widgetRpc)
    .where((event) => event['rpcId'] == 'wheelLanded')
    .map((event) {
      final args = event['args'];
      final item = args is List && args.isNotEmpty ? args.first : null;
      return {
        'wheel': {
          'overlayId': event['overlayId'],
          'widgetId': event['widgetId'],
        },
        'item': item,
      };
    });

bool _matchesWheel(RuntimeMap config, RuntimeMap payload) {
  final expected = config['wheel'];
  final actual = payload['wheel'];
  if (expected is! Map || actual is! Map) return false;
  if (expected['overlayId'] != actual['overlayId'] ||
      expected['widgetId'] != actual['widgetId']) {
    return false;
  }
  final item = config['item']?.toString();
  return item == null || item.isEmpty || item == payload['item']?.toString();
}
