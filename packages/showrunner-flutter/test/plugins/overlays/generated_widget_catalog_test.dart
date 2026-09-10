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
    expect(alert.defaultConfig()['textBelowMedia'], true);
    expect(leaderboard.defaultConfig()['sortOrder'], -1);
    expect((bouncer.defaultConfig()['lifeTime'] as Map)['min'], 7);
    expect(bouncer.defaultSize['height'], 'canvas');
    expect(wheel.defaultSize['width'], 500);
    expect(
      wheel.configSchema.fields.map((field) => field.key),
      contains('slices'),
    );
  });
}
