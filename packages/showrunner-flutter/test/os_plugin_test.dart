import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/plugins/os/manifest.dart';
import 'package:showrunner_flutter/plugins/os/contracts.dart';

void main() {
  test('decodes OS actions into typed configurations', () {
    final plugin = createOsPlugin();
    final powershell = plugin.actions
        .firstWhere((action) => action.actionId.value == 'powershell')
        .decodeConfig({'command': 'Get-Date'});
    expect(powershell, isA<OsPowerShellConfig>());
    expect((powershell as OsPowerShellConfig).command, 'Get-Date');

    final launch = plugin.actions
        .firstWhere((action) => action.actionId.value == 'launch')
        .decodeConfig({
          'application': 'showrunner.exe',
          'args': ['--safe-mode'],
          'ignoreIfRunning': false,
        });
    expect(launch, isA<OsLaunchProcessConfig>());
    expect((launch as OsLaunchProcessConfig).args, ['--safe-mode']);
    expect(launch.ignoreIfRunning, isFalse);
  });

  test('exposes Flutter configuration for OS actions', () {
    final plugin = createOsPlugin();
    final powershell = plugin.actions.firstWhere(
      (action) => action.actionId.value == 'powershell',
    );
    final launch = plugin.actions.firstWhere(
      (action) => action.actionId.value == 'launch',
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
