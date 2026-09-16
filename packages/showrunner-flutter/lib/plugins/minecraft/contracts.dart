import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class MinecraftConnectionSettings {
  const MinecraftConnectionSettings({
    this.host = '',
    this.port = 25575,
    this.password = '',
  });

  factory MinecraftConnectionSettings.fromRuntime(Object? value) {
    final data = value is Map ? value : const <String, dynamic>{};
    return MinecraftConnectionSettings(
      host: data['host']?.toString().trim() ?? '',
      port: _asInt(data['port']) ?? 25575,
      password: data['password']?.toString() ?? '',
    );
  }

  final String host;
  final int port;
  final String password;

  RuntimeMap toRuntime() => {'host': host, 'port': port, 'password': password};
}

final class MinecraftConnectionReference {
  const MinecraftConnectionReference({this.id, this.settings});

  factory MinecraftConnectionReference.fromRuntime(Object? value) {
    if (value is String) {
      return MinecraftConnectionReference(id: value);
    }
    if (value is Map) {
      final data = value['config'] is Map ? value['config'] : value;
      return MinecraftConnectionReference(
        id: value['id']?.toString(),
        settings: MinecraftConnectionSettings.fromRuntime(data),
      );
    }
    return const MinecraftConnectionReference();
  }

  final String? id;
  final MinecraftConnectionSettings? settings;

  Object? toRuntime() => id ?? settings?.toRuntime();
}

final class MinecraftCommandConfig {
  const MinecraftCommandConfig({this.server, this.command = ''});

  factory MinecraftCommandConfig.fromRuntime(RuntimeMap value) =>
      MinecraftCommandConfig(
        server: value.containsKey('server')
            ? MinecraftConnectionReference.fromRuntime(value['server'])
            : null,
        command: value['command']?.toString() ?? '',
      );

  final MinecraftConnectionReference? server;
  final String command;

  RuntimeMap toRuntime() => {
    if (server != null) 'server': server!.toRuntime(),
    'command': command,
  };
}

final class MinecraftConfigCodec<C> implements PluginConfigCodec<C> {
  const MinecraftConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final minecraftCommandConfigCodec = MinecraftConfigCodec(
  MinecraftCommandConfig.fromRuntime,
  (MinecraftCommandConfig value) => value.toRuntime(),
);

int? _asInt(Object? value) => switch (value) {
  int value => value,
  num value => value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};
