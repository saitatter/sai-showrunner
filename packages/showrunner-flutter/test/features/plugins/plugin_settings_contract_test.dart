import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_contract.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

final class _SampleConfig {
  const _SampleConfig(this.message);

  final String message;
}

final class _SampleConfigCodec implements PluginConfigCodec<_SampleConfig> {
  const _SampleConfigCodec();

  @override
  _SampleConfig decode(RuntimeMap value) =>
      _SampleConfig(value['message']?.toString() ?? '');

  @override
  RuntimeMap encode(_SampleConfig value) => {'message': value.message};
}

void main() {
  test('derives stable setting types from declared defaults', () {
    expect(
      const SettingSpec(
        id: SettingId('enabled'),
        displayName: 'Enabled',
        defaultValue: false,
      ).valueType,
      DartSettingType.boolean,
    );
    expect(
      const SettingSpec(
        id: SettingId('port'),
        displayName: 'Port',
        defaultValue: 8390,
      ).valueType,
      DartSettingType.number,
    );
    expect(
      const SettingSpec(
        id: SettingId('enabled'),
        displayName: 'Enabled',
        type: DartSettingType.boolean,
      ).valueType,
      DartSettingType.boolean,
    );
  });

  test(
    'keeps action and trigger payloads typed behind boundary codecs',
    () async {
      final action = ActionSpec<_SampleConfig, int>(
        pluginId: const PluginId('sample'),
        actionId: const ActionId('length'),
        configCodec: const _SampleConfigCodec(),
        invoke: (config, context) async => config.message.length,
      );
      final config = action.decodeConfig({'message': 'hello'});

      expect(await action.invoke(config, EvaluationContext()), 5);
      expect(action.configCodec!.encode(config), {'message': 'hello'});

      final trigger = TriggerSpec<_SampleConfig, String>(
        pluginId: const PluginId('sample'),
        triggerId: const TriggerId('message'),
        displayName: 'Message',
        configCodec: const _SampleConfigCodec(),
        listen: () async* {
          yield 'event';
        },
        listenForConfig: (config) async* {
          yield config.message;
        },
        matches: (config, payload) => payload == config.message,
      );

      expect(await trigger.listenForConfig!.call(config).first, 'hello');
      expect(trigger.matches!.call(config, 'hello'), isTrue);
      expect(
        const SettingSpec<bool>(
          id: SettingId('enabled'),
          displayName: 'Enabled',
        ).valueType,
        DartSettingType.boolean,
      );
      expect(
        const StateSpec<String>(
          id: StateId('status'),
          displayName: 'Status',
          initialValue: 'idle',
        ).initialValue,
        'idle',
      );
    },
  );
}
