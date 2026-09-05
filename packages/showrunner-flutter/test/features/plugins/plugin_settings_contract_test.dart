import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_contract.dart';

void main() {
  test('derives stable setting types from declared defaults', () {
    expect(
      const DartSettingDefinition(
        id: 'enabled',
        displayName: 'Enabled',
        defaultValue: false,
      ).valueType,
      DartSettingType.boolean,
    );
    expect(
      const DartSettingDefinition(
        id: 'port',
        displayName: 'Port',
        defaultValue: 8390,
      ).valueType,
      DartSettingType.number,
    );
    expect(
      const DartSettingDefinition(
        id: 'enabled',
        displayName: 'Enabled',
        type: DartSettingType.boolean,
      ).valueType,
      DartSettingType.boolean,
    );
  });
}
