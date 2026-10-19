import 'dart:convert';
import 'dart:io';

import '../../runtime/expression.dart';
import '../../schema/data_input.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

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

DartPluginManifest createOsPlugin() => DartPluginManifest(
  id: PluginId('os'),
  name: 'Operating System',
  actions: [
    ActionSpec<OsPowerShellConfig, Object?>(
      pluginId: PluginId('os'),
      actionId: ActionId('powershell'),
      displayName: 'PowerShell Command',
      invoke: _runPowershell,
      configSchema: _powerShellConfigSchema,
      configCodec: osPowerShellConfigCodec,
    ),
    ActionSpec<OsLaunchProcessConfig, Object?>(
      pluginId: PluginId('os'),
      actionId: ActionId('launchProcess'),
      displayName: 'Launch Process',
      invoke: _launchProcess,
      configSchema: _launchConfigSchema,
      configCodec: osLaunchProcessConfigCodec,
    ),
    ActionSpec<OsLaunchProcessConfig, Object?>(
      pluginId: PluginId('os'),
      actionId: ActionId('launch'),
      displayName: 'Launch App',
      invoke: _launchProcess,
      configSchema: _launchConfigSchema,
      configCodec: osLaunchProcessConfigCodec,
    ),
  ],
);

Future<Object?> _runPowershell(
  OsPowerShellConfig config,
  EvaluationContext context,
) async {
  final command = config.command ?? '';
  if (command.isEmpty) return {'executed': false};
  if (!Platform.isWindows) {
    return {'executed': false, 'reason': 'Windows required'};
  }
  context.cancellationToken?.throwIfCancelled();
  final process = await Process.start('powershell.exe', ['-Command', command]);
  void abort() {
    process.kill();
  }

  final token = context.cancellationToken;
  token?.addListener(abort);
  try {
    final output = await Future.wait<Object?>([
      process.stdout.transform(utf8.decoder).join(),
      process.stderr.transform(utf8.decoder).join(),
      process.exitCode,
    ]);
    token?.throwIfCancelled();
    return {'processOutput': output[0]?.toString() ?? ''};
  } finally {
    token?.removeListener(abort);
  }
}

Future<Object?> _launchProcess(
  OsLaunchProcessConfig config,
  EvaluationContext context,
) async {
  context.cancellationToken?.throwIfCancelled();
  final path = config.path ?? config.application ?? '';
  if (path.isEmpty) return {'launched': false};
  final ignoreIfRunning = config.ignoreIfRunning;
  if (ignoreIfRunning && await isProcessRunning(_fileName(path))) {
    return {'launched': false, 'reason': 'already-running'};
  }
  final args = config.args;
  final configuredDirectory = config.dir?.trim() ?? '';
  final workingDirectory = configuredDirectory.isEmpty
      ? File(path).absolute.parent.path
      : configuredDirectory;
  await Process.start(
    'cmd.exe',
    ['/c', 'start', 'ShowRunner Launch', path, ...args],
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.detached,
  );
  return {'launched': true, 'path': path, 'args': args};
}

Future<bool> isProcessRunning(String application) async {
  if (!Platform.isWindows || application.trim().isEmpty) return false;
  final result = await Process.run('tasklist', const <String>[]);
  return result.stdout.toString().toLowerCase().contains(
    application.trim().toLowerCase(),
  );
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
