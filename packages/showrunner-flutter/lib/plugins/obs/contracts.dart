import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class ObsEmptyConfig {
  const ObsEmptyConfig();
}

enum ObsToggleMode { enabled, disabled, toggle }

ObsToggleMode obsToggleModeFromRuntime(Object? value) =>
    switch (value?.toString().toLowerCase()) {
      'true' => ObsToggleMode.enabled,
      'false' => ObsToggleMode.disabled,
      'toggle' => ObsToggleMode.toggle,
      _ => value == true ? ObsToggleMode.enabled : ObsToggleMode.disabled,
    };

Object obsToggleModeToRuntime(ObsToggleMode value) => switch (value) {
  ObsToggleMode.enabled => true,
  ObsToggleMode.disabled => false,
  ObsToggleMode.toggle => 'toggle',
};

final class ObsToggleConfig {
  const ObsToggleConfig(this.mode);

  final ObsToggleMode mode;
}

final class ObsStudioModeConfig {
  const ObsStudioModeConfig({required this.mode, this.studioModeEnabled});

  final ObsToggleMode mode;
  final bool? studioModeEnabled;
}

final class ObsHotkeyConfig {
  const ObsHotkeyConfig({this.hotkey});

  factory ObsHotkeyConfig.fromRuntime(RuntimeMap value) =>
      ObsHotkeyConfig(hotkey: _string(value['hotkey']));

  final String? hotkey;

  RuntimeMap toRuntime() => {if (hotkey != null) 'hotkey': hotkey};
}

final class ObsChapterMarkerConfig {
  const ObsChapterMarkerConfig({this.chapterName});

  factory ObsChapterMarkerConfig.fromRuntime(RuntimeMap value) =>
      ObsChapterMarkerConfig(chapterName: _string(value['chapterName']));

  final String? chapterName;

  RuntimeMap toRuntime() => {
    if (chapterName != null) 'chapterName': chapterName,
  };
}

final class ObsScreenshotConfig {
  const ObsScreenshotConfig({
    this.sourceName,
    this.width,
    this.height,
    this.directory,
    this.filename,
  });

  factory ObsScreenshotConfig.fromRuntime(RuntimeMap value) =>
      ObsScreenshotConfig(
        sourceName: _string(value['sourceName']),
        width: _number(value['width']),
        height: _number(value['height']),
        directory: _string(value['directory']),
        filename: _string(value['filename']),
      );

  final String? sourceName;
  final num? width;
  final num? height;
  final String? directory;
  final String? filename;

  RuntimeMap toRuntime() => {
    if (sourceName != null) 'sourceName': sourceName,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (directory != null) 'directory': directory,
    if (filename != null) 'filename': filename,
  };
}

final class ObsConfigCodec<C> implements PluginConfigCodec<C> {
  const ObsConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

ObsConfigCodec<ObsToggleConfig> obsToggleConfigCodec(String key) =>
    ObsConfigCodec(
      (value) => ObsToggleConfig(obsToggleModeFromRuntime(value[key])),
      (value) => {key: obsToggleModeToRuntime(value.mode)},
    );

final obsStudioModeConfigCodec = ObsConfigCodec(
  (value) => ObsStudioModeConfig(
    mode: obsToggleModeFromRuntime(value['studioMode']),
    studioModeEnabled: _bool(value['studioModeEnabled']),
  ),
  (value) => {
    'studioMode': obsToggleModeToRuntime(value.mode),
    if (value.studioModeEnabled != null)
      'studioModeEnabled': value.studioModeEnabled,
  },
);

final obsEmptyConfigCodec = ObsConfigCodec(
  (value) => const ObsEmptyConfig(),
  (ObsEmptyConfig value) => const <String, dynamic>{},
);
final obsHotkeyConfigCodec = ObsConfigCodec(
  ObsHotkeyConfig.fromRuntime,
  (ObsHotkeyConfig value) => value.toRuntime(),
);
final obsChapterMarkerConfigCodec = ObsConfigCodec(
  ObsChapterMarkerConfig.fromRuntime,
  (ObsChapterMarkerConfig value) => value.toRuntime(),
);
final obsScreenshotConfigCodec = ObsConfigCodec(
  ObsScreenshotConfig.fromRuntime,
  (ObsScreenshotConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();

num? _number(Object? value) => value is num ? value : num.tryParse('$value');

bool? _bool(Object? value) => value is bool ? value : null;
