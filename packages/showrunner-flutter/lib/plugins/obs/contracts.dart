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

final class ObsSceneConfig {
  const ObsSceneConfig({this.scene});

  factory ObsSceneConfig.fromRuntime(RuntimeMap value) =>
      ObsSceneConfig(scene: _string(value['scene']));

  final String? scene;

  RuntimeMap toRuntime() => {if (scene != null) 'scene': scene};
}

final class ObsSourceVisibilityConfig {
  const ObsSourceVisibilityConfig({
    this.scene,
    this.source,
    required this.mode,
  });

  factory ObsSourceVisibilityConfig.fromRuntime(RuntimeMap value) =>
      ObsSourceVisibilityConfig(
        scene: _string(value['scene']),
        source: _integer(value['source']),
        mode: obsToggleModeFromRuntime(value['enabled']),
      );

  final String? scene;
  final int? source;
  final ObsToggleMode mode;

  RuntimeMap toRuntime() => {
    if (scene != null) 'scene': scene,
    if (source != null) 'source': source,
    'enabled': obsToggleModeToRuntime(mode),
  };
}

final class ObsSourceNameConfig {
  const ObsSourceNameConfig({this.sourceName});

  factory ObsSourceNameConfig.fromRuntime(RuntimeMap value) =>
      ObsSourceNameConfig(sourceName: _string(value['sourceName']));

  final String? sourceName;

  RuntimeMap toRuntime() => {if (sourceName != null) 'sourceName': sourceName};
}

final class ObsInputSettingsConfig {
  const ObsInputSettingsConfig({
    this.sourceName,
    this.inputSettings = const {},
  });

  factory ObsInputSettingsConfig.fromRuntime(RuntimeMap value) =>
      ObsInputSettingsConfig(
        sourceName: _string(value['sourceName']),
        inputSettings: _map(value['inputSettings']),
      );

  final String? sourceName;
  final RuntimeMap inputSettings;

  RuntimeMap toRuntime() => {
    if (sourceName != null) 'sourceName': sourceName,
    'inputSettings': inputSettings,
  };
}

final class ObsFilterConfig {
  const ObsFilterConfig({this.sourceName, this.filterName, required this.mode});

  factory ObsFilterConfig.fromRuntime(RuntimeMap value) => ObsFilterConfig(
    sourceName: _string(value['sourceName']),
    filterName: _string(value['filterName']),
    mode: obsToggleModeFromRuntime(value['filterEnabled']),
  );

  final String? sourceName;
  final String? filterName;
  final ObsToggleMode mode;

  RuntimeMap toRuntime() => {
    if (sourceName != null) 'sourceName': sourceName,
    if (filterName != null) 'filterName': filterName,
    'filterEnabled': obsToggleModeToRuntime(mode),
  };
}

final class ObsTextConfig {
  const ObsTextConfig({this.sourceName, this.text});

  factory ObsTextConfig.fromRuntime(RuntimeMap value) => ObsTextConfig(
    sourceName: _string(value['sourceName']),
    text: _string(value['text']),
  );

  final String? sourceName;
  final String? text;

  RuntimeMap toRuntime() => {
    if (sourceName != null) 'sourceName': sourceName,
    if (text != null) 'text': text,
  };
}

enum ObsMediaAction { play, pause, restart, stop, next, previous }

ObsMediaAction obsMediaActionFromRuntime(Object? value) =>
    switch (value?.toString().toLowerCase()) {
      'pause' => ObsMediaAction.pause,
      'restart' => ObsMediaAction.restart,
      'stop' => ObsMediaAction.stop,
      'next' => ObsMediaAction.next,
      'previous' => ObsMediaAction.previous,
      _ => ObsMediaAction.play,
    };

String obsMediaActionToRuntime(ObsMediaAction value) => switch (value) {
  ObsMediaAction.play => 'Play',
  ObsMediaAction.pause => 'Pause',
  ObsMediaAction.restart => 'Restart',
  ObsMediaAction.stop => 'Stop',
  ObsMediaAction.next => 'Next',
  ObsMediaAction.previous => 'Previous',
};

final class ObsMediaActionConfig {
  const ObsMediaActionConfig({this.source, required this.action});

  factory ObsMediaActionConfig.fromRuntime(RuntimeMap value) =>
      ObsMediaActionConfig(
        source: _string(value['source']),
        action: obsMediaActionFromRuntime(value['action']),
      );

  final String? source;
  final ObsMediaAction action;

  RuntimeMap toRuntime() => {
    if (source != null) 'source': source,
    'action': obsMediaActionToRuntime(action),
  };
}

final class ObsPlayMediaConfig {
  const ObsPlayMediaConfig({this.scene, this.source, this.sourceName});

  factory ObsPlayMediaConfig.fromRuntime(RuntimeMap value) =>
      ObsPlayMediaConfig(
        scene: _string(value['scene']),
        source: _integer(value['source']),
        sourceName: _string(value['sourceName']),
      );

  final String? scene;
  final int? source;
  final String? sourceName;

  RuntimeMap toRuntime() => {
    if (scene != null) 'scene': scene,
    if (source != null) 'source': source,
    if (sourceName != null) 'sourceName': sourceName,
  };
}

final class ObsMuteConfig {
  const ObsMuteConfig({this.source, required this.mode});

  factory ObsMuteConfig.fromRuntime(RuntimeMap value) => ObsMuteConfig(
    source: _string(value['source']),
    mode: obsToggleModeFromRuntime(value['muted']),
  );

  final String? source;
  final ObsToggleMode mode;

  RuntimeMap toRuntime() => {
    if (source != null) 'source': source,
    'muted': obsToggleModeToRuntime(mode),
  };
}

final class ObsVolumeConfig {
  const ObsVolumeConfig({this.source, this.volume});

  factory ObsVolumeConfig.fromRuntime(RuntimeMap value) => ObsVolumeConfig(
    source: _string(value['source']),
    volume: _number(value['volume']),
  );

  final String? source;
  final num? volume;

  RuntimeMap toRuntime() => {
    if (source != null) 'source': source,
    if (volume != null) 'volume': volume,
  };
}

final class ObsSourceUrlConfig {
  const ObsSourceUrlConfig({this.source, this.url});

  factory ObsSourceUrlConfig.fromRuntime(RuntimeMap value) =>
      ObsSourceUrlConfig(
        source: _string(value['source']),
        url: _string(value['url']),
      );

  final String? source;
  final String? url;

  RuntimeMap toRuntime() => {
    if (source != null) 'source': source,
    if (url != null) 'url': url,
  };
}

final class ObsNamedUrlConfig {
  const ObsNamedUrlConfig({this.sourceName, this.url});

  factory ObsNamedUrlConfig.fromRuntime(RuntimeMap value) => ObsNamedUrlConfig(
    sourceName: _string(value['sourceName']),
    url: _string(value['url']),
  );

  final String? sourceName;
  final String? url;

  RuntimeMap toRuntime() => {
    if (sourceName != null) 'sourceName': sourceName,
    if (url != null) 'url': url,
  };
}

final class ObsImageConfig {
  const ObsImageConfig({this.sourceName, this.image});

  factory ObsImageConfig.fromRuntime(RuntimeMap value) => ObsImageConfig(
    sourceName: _string(value['sourceName']),
    image: _string(value['image']),
  );

  final String? sourceName;
  final String? image;

  RuntimeMap toRuntime() => {
    if (sourceName != null) 'sourceName': sourceName,
    if (image != null) 'image': image,
  };
}

final class ObsTransformConfig {
  const ObsTransformConfig({
    this.scene,
    this.source,
    this.transform = const {},
  });

  factory ObsTransformConfig.fromRuntime(RuntimeMap value) =>
      ObsTransformConfig(
        scene: _string(value['scene']),
        source: _integer(value['source']),
        transform: _map(value['transform']),
      );

  final String? scene;
  final int? source;
  final RuntimeMap transform;

  RuntimeMap toRuntime() => {
    if (scene != null) 'scene': scene,
    if (source != null) 'source': source,
    'transform': transform,
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
final obsSceneConfigCodec = ObsConfigCodec(
  ObsSceneConfig.fromRuntime,
  (ObsSceneConfig value) => value.toRuntime(),
);
final obsSourceVisibilityConfigCodec = ObsConfigCodec(
  ObsSourceVisibilityConfig.fromRuntime,
  (ObsSourceVisibilityConfig value) => value.toRuntime(),
);
final obsSourceNameConfigCodec = ObsConfigCodec(
  ObsSourceNameConfig.fromRuntime,
  (ObsSourceNameConfig value) => value.toRuntime(),
);
final obsInputSettingsConfigCodec = ObsConfigCodec(
  ObsInputSettingsConfig.fromRuntime,
  (ObsInputSettingsConfig value) => value.toRuntime(),
);
final obsFilterConfigCodec = ObsConfigCodec(
  ObsFilterConfig.fromRuntime,
  (ObsFilterConfig value) => value.toRuntime(),
);
final obsTextConfigCodec = ObsConfigCodec(
  ObsTextConfig.fromRuntime,
  (ObsTextConfig value) => value.toRuntime(),
);
final obsMediaActionConfigCodec = ObsConfigCodec(
  ObsMediaActionConfig.fromRuntime,
  (ObsMediaActionConfig value) => value.toRuntime(),
);
final obsPlayMediaConfigCodec = ObsConfigCodec(
  ObsPlayMediaConfig.fromRuntime,
  (ObsPlayMediaConfig value) => value.toRuntime(),
);
final obsMuteConfigCodec = ObsConfigCodec(
  ObsMuteConfig.fromRuntime,
  (ObsMuteConfig value) => value.toRuntime(),
);
final obsVolumeConfigCodec = ObsConfigCodec(
  ObsVolumeConfig.fromRuntime,
  (ObsVolumeConfig value) => value.toRuntime(),
);
final obsSourceUrlConfigCodec = ObsConfigCodec(
  ObsSourceUrlConfig.fromRuntime,
  (ObsSourceUrlConfig value) => value.toRuntime(),
);
final obsNamedUrlConfigCodec = ObsConfigCodec(
  ObsNamedUrlConfig.fromRuntime,
  (ObsNamedUrlConfig value) => value.toRuntime(),
);
final obsImageConfigCodec = ObsConfigCodec(
  ObsImageConfig.fromRuntime,
  (ObsImageConfig value) => value.toRuntime(),
);
final obsTransformConfigCodec = ObsConfigCodec(
  ObsTransformConfig.fromRuntime,
  (ObsTransformConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();

num? _number(Object? value) => value is num ? value : num.tryParse('$value');

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

RuntimeMap _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

bool? _bool(Object? value) => value is bool ? value : null;
