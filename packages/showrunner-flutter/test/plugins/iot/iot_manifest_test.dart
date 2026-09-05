import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/plugins/iot/manifest.dart';

void main() {
  test('generic IoT actions select persisted Light and Plug resources', () {
    final plugin = createIotPlugin(
      resolver: (resourceType, resourceId, config, context) async => {
        'resourceType': resourceType,
        'resourceId': resourceId,
      },
    );

    final light = plugin.actions.firstWhere(
      (action) => action.actionId == 'light',
    );
    final plug = plugin.actions.firstWhere(
      (action) => action.actionId == 'plug',
    );

    expect(light.configSchema?.fields.first.kind, DartDataInputKind.resource);
    expect(light.configSchema?.fields.first.resourceType, 'Light');
    expect(plug.configSchema?.fields.first.kind, DartDataInputKind.resource);
    expect(plug.configSchema?.fields.first.resourceType, 'Plug');
  });
}
