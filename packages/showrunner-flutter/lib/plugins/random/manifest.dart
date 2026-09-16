import 'dart:math';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../overlays/manifest.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

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
      id: PluginId('random'),
      name: 'Random',
      actions: [
        ActionSpec<RandomRangeConfig, RuntimeMap>(
          pluginId: PluginId('random'),
          actionId: ActionId('random'),
          displayName: 'Random Decision',
          invoke: _random,
          configSchema: _randomSchema,
          configCodec: randomRangeConfigCodec,
        ),
        ActionSpec<RandomWheelConfig, RuntimeMap>(
          pluginId: PluginId('random'),
          actionId: ActionId('spinWheel'),
          displayName: 'Spin Wheel',
          invoke: (config, context) => _spinWheel(eventHub, config, context),
          configSchema: _spinWheelSchema,
          configCodec: randomWheelConfigCodec,
        ),
      ],
      triggers: eventHub == null
          ? const []
          : [
              TriggerSpec<RandomWheelTriggerConfig, RandomWheelLandedEvent>(
                pluginId: PluginId('random'),
                triggerId: TriggerId('wheelLanded'),
                displayName: 'Wheel Stopped',
                configSchema: _wheelTriggerSchema,
                listen: () => _wheelEvents(eventHub),
                matches: _matchesWheel,
                eventDecoder: RandomWheelLandedEvent.fromRuntime,
                eventEncoder: (event) => event.toRuntime(),
                configCodec: randomWheelTriggerConfigCodec,
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

Future<RuntimeMap> _random(
  RandomRangeConfig config,
  EvaluationContext context,
) async {
  final minVal = config.min.toDouble();
  final maxVal = config.max.toDouble();
  final value = minVal + _randomGenerator.nextDouble() * (maxVal - minVal);
  return {'value': value};
}

Future<RuntimeMap> _spinWheel(
  DartPluginEventHub? eventHub,
  RandomWheelConfig config,
  EvaluationContext context,
) async {
  final strength = config.strength.toDouble();
  final wheel = config.wheel;
  if (eventHub != null && wheel?.isValid == true) {
    eventHub.emit(OverlayEventIds.widgetRpc, {
      'overlayId': wheel!.overlayId,
      'widgetId': wheel.widgetId,
      'rpcId': 'spinWheel',
      'args': [strength],
    });
  }
  return {'spun': true, 'strength': strength};
}

Stream<RandomWheelLandedEvent> _wheelEvents(DartPluginEventHub eventHub) =>
    eventHub
        .stream(OverlayEventIds.widgetRpc)
        .where((event) => event['rpcId'] == 'wheelLanded')
        .map((event) {
          final args = event['args'];
          final item = args is List && args.isNotEmpty ? args.first : null;
          return RandomWheelLandedEvent(
            wheel: RandomWheelTarget(
              overlayId: event['overlayId']?.toString(),
              widgetId: event['widgetId']?.toString(),
            ),
            item: item?.toString(),
          );
        });

bool _matchesWheel(
  RandomWheelTriggerConfig config,
  RandomWheelLandedEvent payload,
) {
  if (config.wheel.overlayId != payload.wheel.overlayId ||
      config.wheel.widgetId != payload.wheel.widgetId) {
    return false;
  }
  final item = config.item?.trim();
  return item == null || item.isEmpty || item == payload.item;
}
