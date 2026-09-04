import 'dart:io';

import '../../runtime/expression.dart';
import '../../components/data_inputs/data_input.dart';
import '../registry/plugin_registry.dart';

const _powerShellConfigSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Command',
      key: 'command',
      kind: DartDataInputKind.multilineText,
      required: true,
      defaultValue: '',
    ),
    DartDataInputSchema(
      label: 'Working Directory',
      key: 'cwd',
      kind: DartDataInputKind.filePath,
    ),
  ],
);

const _launchConfigSchema = DartDataInputSchema(
  label: 'Launch App',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Application',
      key: 'application',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Working Directory',
      key: 'dir',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Arguments',
      key: 'args',
      kind: DartDataInputKind.array,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Ignore If Already Running',
      key: 'ignoreIfRunning',
      kind: DartDataInputKind.boolean,
      required: true,
      defaultValue: true,
    ),
  ],
);

DartPluginManifest createOsPlugin() => const DartPluginManifest(
  id: 'os',
  name: 'Operating System',
  actions: [
    DartActionDefinition(
      pluginId: 'os',
      actionId: 'powershell',
      displayName: 'PowerShell Command',
      invoke: _runPowershell,
      configSchema: _powerShellConfigSchema,
    ),
    DartActionDefinition(
      pluginId: 'os',
      actionId: 'launchProcess',
      displayName: 'Launch Process',
      invoke: _launchProcess,
      configSchema: _launchConfigSchema,
    ),
    DartActionDefinition(
      pluginId: 'os',
      actionId: 'launch',
      displayName: 'Launch App',
      invoke: _launchProcess,
      configSchema: _launchConfigSchema,
    ),
  ],
);

Future<Object?> _runPowershell(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final command = config['command']?.toString() ?? '';
  if (command.isEmpty) return {'executed': false};
  if (!Platform.isWindows) {
    return {'executed': false, 'reason': 'Windows required'};
  }
  final result = await Process.run('powershell.exe', ['-Command', command]);
  return {
    'executed': true,
    'exitCode': result.exitCode,
    'stdout': result.stdout?.toString(),
    'stderr': result.stderr?.toString(),
  };
}

Future<Object?> _launchProcess(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final path = (config['path'] ?? config['application'])?.toString() ?? '';
  if (path.isEmpty) return {'launched': false};
  final args = config['args'] is List
      ? (config['args'] as List).map((item) => item.toString()).toList()
      : const <String>[];
  final workingDirectory = config['dir']?.toString();
  await Process.start(path, args, workingDirectory: workingDirectory);
  return {'launched': true, 'path': path, 'args': args};
}
