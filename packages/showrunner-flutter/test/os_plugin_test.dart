import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/plugins/os/manifest.dart';

void main() {
  test('exposes Flutter configuration for migrated OS actions', () {
    final plugin = createOsPlugin();
    final powershell = plugin.actions.firstWhere(
      (action) => action.actionId == 'powershell',
    );
    final launch = plugin.actions.firstWhere(
      (action) => action.actionId == 'launch',
    );

    expect(powershell.configSchema?.fields.map((field) => field.key), [
      'command',
      'cwd',
    ]);
    expect(
      powershell.configSchema?.fields.first.kind,
      DartDataInputKind.multilineText,
    );
    expect(launch.configSchema?.fields.map((field) => field.key), [
      'application',
      'dir',
      'args',
      'ignoreIfRunning',
    ]);
    expect(launch.configSchema?.fields.last.defaultValue, isTrue);
  });
}
