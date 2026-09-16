import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class TwinklyActionConfig {
  const TwinklyActionConfig({this.ip, this.color, this.movieId, this.movie});

  factory TwinklyActionConfig.fromRuntime(RuntimeMap value) =>
      TwinklyActionConfig(
        ip: value['ip']?.toString(),
        color: value['color']?.toString(),
        movieId: value['movieId']?.toString(),
        movie: value['movie']?.toString(),
      );

  final String? ip;
  final String? color;
  final String? movieId;
  final String? movie;

  RuntimeMap toRuntime() => {
    if (ip != null) 'ip': ip,
    if (color != null) 'color': color,
    if (movieId != null) 'movieId': movieId,
    if (movie != null) 'movie': movie,
  };
}

final class TwinklyConfigCodec<C> implements PluginConfigCodec<C> {
  const TwinklyConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final twinklyActionConfigCodec = TwinklyConfigCodec(
  TwinklyActionConfig.fromRuntime,
  (TwinklyActionConfig value) => value.toRuntime(),
);
