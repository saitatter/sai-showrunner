import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class DiscordMessageConfig {
  const DiscordMessageConfig({
    this.webhook,
    this.webhookUrl,
    this.message,
    this.files,
    this.username,
    this.avatarUrl,
    this.tts,
  });

  factory DiscordMessageConfig.fromRuntime(RuntimeMap value) {
    final rawFiles = value['files'];
    final files = rawFiles is List
        ? rawFiles
              .map((file) => file.toString().trim())
              .where((file) => file.isNotEmpty)
              .toList(growable: false)
        : null;
    return DiscordMessageConfig(
      webhook: value['webhook'],
      webhookUrl: value['webhookUrl']?.toString(),
      message: value['message']?.toString(),
      files: files,
      username: value['username']?.toString(),
      avatarUrl: value['avatarUrl']?.toString(),
      tts: value['tts'] is bool ? value['tts'] as bool : null,
    );
  }

  final Object? webhook;
  final String? webhookUrl;
  final String? message;
  final List<String>? files;
  final String? username;
  final String? avatarUrl;
  final bool? tts;

  RuntimeMap toRuntime() => {
    if (webhook != null) 'webhook': webhook,
    if (webhookUrl != null) 'webhookUrl': webhookUrl,
    if (message != null) 'message': message,
    if (files != null) 'files': files,
    if (username != null) 'username': username,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    if (tts != null) 'tts': tts,
  };
}

final class DiscordConfigCodec<C> implements PluginConfigCodec<C> {
  const DiscordConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final discordMessageConfigCodec = DiscordConfigCodec(
  DiscordMessageConfig.fromRuntime,
  (DiscordMessageConfig value) => value.toRuntime(),
);
