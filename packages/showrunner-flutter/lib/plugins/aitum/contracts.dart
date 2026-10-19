import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class AitumSceneConfig {
  const AitumSceneConfig({this.scene = ''});

  factory AitumSceneConfig.fromRuntime(RuntimeMap value) =>
      AitumSceneConfig(scene: value['scene']?.toString() ?? '');

  final String scene;

  RuntimeMap toRuntime() => {'scene': scene};
}

enum AitumToggleMode { enabled, disabled, toggle }

AitumToggleMode aitumToggleModeFromRuntime(Object? value) =>
    switch (value?.toString().toLowerCase()) {
      'false' => AitumToggleMode.disabled,
      'toggle' => AitumToggleMode.toggle,
      _ => AitumToggleMode.enabled,
    };

final class AitumToggleConfig {
  const AitumToggleConfig({this.mode = AitumToggleMode.enabled});

  factory AitumToggleConfig.fromRuntime(RuntimeMap value) =>
      AitumToggleConfig(mode: aitumToggleModeFromRuntime(value['streaming']));

  final AitumToggleMode mode;

  RuntimeMap toRuntime() => {
    'streaming': switch (mode) {
      AitumToggleMode.enabled => true,
      AitumToggleMode.disabled => false,
      AitumToggleMode.toggle => 'toggle',
    },
  };
}

final class AitumChapterConfig {
  const AitumChapterConfig({this.chapterName = ''});

  factory AitumChapterConfig.fromRuntime(RuntimeMap value) =>
      AitumChapterConfig(chapterName: value['chapterName']?.toString() ?? '');

  final String chapterName;

  RuntimeMap toRuntime() => {'chapterName': chapterName};
}

final class AitumEmptyConfig {
  const AitumEmptyConfig();

  factory AitumEmptyConfig.fromRuntime(RuntimeMap value) =>
      const AitumEmptyConfig();

  RuntimeMap toRuntime() => {};
}

final class AitumConfigCodec<C> implements PluginConfigCodec<C> {
  const AitumConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final aitumSceneConfigCodec = AitumConfigCodec(
  AitumSceneConfig.fromRuntime,
  (AitumSceneConfig value) => value.toRuntime(),
);
final aitumToggleConfigCodec = AitumConfigCodec(
  AitumToggleConfig.fromRuntime,
  (AitumToggleConfig value) => value.toRuntime(),
);
final aitumChapterConfigCodec = AitumConfigCodec(
  AitumChapterConfig.fromRuntime,
  (AitumChapterConfig value) => value.toRuntime(),
);
final aitumEmptyConfigCodec = AitumConfigCodec(
  AitumEmptyConfig.fromRuntime,
  (AitumEmptyConfig value) => value.toRuntime(),
);
