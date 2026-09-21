import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generated Flutter catalog contains the browser widget registry',
    () async {
      final widgets = await GeneratedOverlayWidgetCatalog.load();
      final keys = widgets.map((widget) => widget.key).toSet();

      expect(
        keys,
        containsAll(<String>[
          'overlays.alert',
          'overlays.chatFeed',
          'overlays.shaderLayer',
          'random.wheel',
          'heartrate.heartRate',
          'heartrate.heartRateGraph',
          'heartrate.heartRateZone',
        ]),
      );
      expect(
        widgets
            .firstWhere((widget) => widget.key == 'overlays.chatFeed')
            .config['fontSize']['default'],
        24,
      );
      expect(
        widgets
            .firstWhere((widget) => widget.key == 'random.wheel')
            .capabilities['commands'],
        contains('spinWheel'),
      );
      expect(
        widgets
            .firstWhere((widget) => widget.key == 'heartrate.heartRate')
            .config['showLabel']['default'],
        true,
      );
      expect(
        widgets
            .firstWhere((widget) => widget.key == 'heartrate.heartRateGraph')
            .config['maxBpm']['default'],
        200,
      );
      final heartRate = widgets.firstWhere(
        (widget) => widget.key == 'heartrate.heartRate',
      );
      expect(heartRate.config['animate']['default'], true);
      expect(heartRate.config['showBattery']['default'], false);
      expect(heartRate.capabilities['states'], [
        'heartRate',
        'connection',
        'device',
      ]);
    },
  );

  test('creates defaults from generated widget metadata', () async {
    final widgets = await GeneratedOverlayWidgetCatalog.load();
    final shader = widgets.firstWhere(
      (definition) => definition.key == 'overlays.shaderLayer',
    );
    final config = shader.defaultConfig();
    final widget = shader.createWidget(widgetId: 'shader-1');

    expect(config['preset'], 'aurora');
    expect(config['blendMode'], 'normal');
    expect(widget['id'], 'shader-1');
    expect(widget['plugin'], 'overlays');
    expect((widget['size'] as Map)['height'], 500);
    expect((widget['config'] as Map)['accentColor'], '#9146ff');
  });

  test('keeps generated widgets editable through generic schemas', () async {
    final widgets = await GeneratedOverlayWidgetCatalog.load();
    final bar = widgets.firstWhere(
      (definition) => definition.key == 'overlays.bar',
    );
    final alert = widgets.firstWhere(
      (definition) => definition.key == 'overlays.alert',
    );
    final leaderboard = widgets.firstWhere(
      (definition) => definition.key == 'overlays.leaderboard',
    );
    final bouncer = widgets.firstWhere(
      (definition) => definition.key == 'overlays.emote-bounce',
    );
    final wheel = widgets.firstWhere(
      (definition) => definition.key == 'random.wheel',
    );

    expect(bar.defaultConfig()['direction'], 'Right');
    expect(
      bar.configSchema.fields
          .firstWhere((field) => field.key == 'outerRadius')
          .fields
          .map((field) => field.key),
      containsAll(<String>['topLeft', 'topRight', 'bottomLeft', 'bottomRight']),
    );
    expect(alert.defaultConfig()['textBelowMedia'], true);
    expect(leaderboard.defaultConfig()['sortOrder'], -1);
    final leaderboardVariables = leaderboard.configSchema.fields
        .firstWhere((field) => field.key == 'variables');
    expect(
      leaderboardVariables.itemSchema?.fields.map((field) => field.key),
      containsAll(<String>['variable', 'font', 'textAlign', 'background', 'block']),
    );
    expect((bouncer.defaultConfig()['lifeTime'] as Map)['min'], 7);
    expect(
      bouncer.configSchema.fields
          .firstWhere((field) => field.key == 'spamPrevention')
          .fields
          .map((field) => field.key),
      containsAll(<String>['emoteRatio', 'emoteCap', 'emoteCapPerMessage']),
    );
    expect(
      bouncer.configSchema.fields
          .firstWhere((field) => field.key == 'launchers')
          .itemSchema
          ?.fields
          .map((field) => field.key),
      containsAll(<String>['x', 'y', 'angle', 'spread', 'velocity']),
    );
    expect(bouncer.defaultSize['height'], 'canvas');
    expect(wheel.defaultSize['width'], 500);
    expect(
      wheel.configSchema.fields.map((field) => field.key),
      contains('slices'),
    );

    final label = widgets.firstWhere(
      (definition) => definition.key == 'overlays.label',
    );
    final labelConfig = label.defaultConfig();
    expect(labelConfig['message'], 'Label');
    expect((labelConfig['font'] as Map)['fontFamily'], 'Impact');
    expect((labelConfig['font'] as Map)['stroke'], {
      'width': 4,
      'color': '#000000',
    });
    expect(labelConfig['textAlign'], {'textAlign': 'left'});
    expect((labelConfig['block'] as Map)['verticalAlign'], 'top');
    expect(
      label.configSchema.fields.map((field) => field.key),
      containsAll(<String>['message', 'font', 'textAlign', 'block']),
    );
  });
}
