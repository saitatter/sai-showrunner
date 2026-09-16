import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class OsPowerShellConfig {
  const OsPowerShellConfig({this.command, this.cwd});

  factory OsPowerShellConfig.fromRuntime(RuntimeMap value) =>
      OsPowerShellConfig(
        command: _string(value['command']),
        cwd: _string(value['cwd']),
      );

  final String? command;
  final String? cwd;

  RuntimeMap toRuntime() => {
    if (command != null) 'command': command,
    if (cwd != null) 'cwd': cwd,
  };
}

final class OsLaunchProcessConfig {
  const OsLaunchProcessConfig({
    this.application,
    this.path,
    this.dir,
    this.args = const [],
    this.ignoreIfRunning = true,
  });

  factory OsLaunchProcessConfig.fromRuntime(RuntimeMap value) =>
      OsLaunchProcessConfig(
        application: _string(value['application']),
        path: _string(value['path']),
        dir: _string(value['dir']),
        args: value['args'] is List
            ? (value['args'] as List).map((item) => item.toString()).toList()
            : const [],
        ignoreIfRunning: _bool(value['ignoreIfRunning']),
      );

  final String? application;
  final String? path;
  final String? dir;
  final List<String> args;
  final bool ignoreIfRunning;

  RuntimeMap toRuntime() => {
    if (application != null) 'application': application,
    if (path != null) 'path': path,
    if (dir != null) 'dir': dir,
    'args': args,
    'ignoreIfRunning': ignoreIfRunning,
  };
}

final class OsConfigCodec<C> implements PluginConfigCodec<C> {
  const OsConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final osPowerShellConfigCodec = OsConfigCodec(
  OsPowerShellConfig.fromRuntime,
  (OsPowerShellConfig value) => value.toRuntime(),
);
final osLaunchProcessConfigCodec = OsConfigCodec(
  OsLaunchProcessConfig.fromRuntime,
  (OsLaunchProcessConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();

bool _bool(Object? value) =>
    value is bool ? value : value?.toString().trim().toLowerCase() != 'false';
