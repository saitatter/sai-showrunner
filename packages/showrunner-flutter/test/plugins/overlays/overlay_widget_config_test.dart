import 'package:flutter_test/flutter_test.dart';

import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exposes the generated overlay widget catalog', () async {
    final widgets = await GeneratedOverlayWidgetCatalog.load();
    final keys = widgets.map((definition) => definition.key).toSet();
    expect(
      keys,
      containsAll(<String>[
        'overlays.label',
        'overlays.chatFeed',
        'overlays.paidAlert',
        'overlays.sceneBanner',
        'overlays.shaderLayer',
        'overlays.bar',
        'overlays.alert',
        'overlays.leaderboard',
        'overlays.emote-bounce',
        'random.wheel',
      ]),
    );
    expect(
      widgets
          .firstWhere((definition) => definition.key == 'overlays.chatFeed')
          .defaultSize['width'],
      900,
    );
    expect(
      widgets.where((definition) => definition.key == 'unknown.chatFeed'),
      isEmpty,
    );
    expect(
      widgets
          .firstWhere((definition) => definition.key == 'overlays.chatFeed')
          .configSchema
          .fields
          .firstWhere((field) => field.key == 'fontFamily')
          .label,
      'Font Family',
    );
  });

  test('creates defaults compatible with the overlay widget runtime', () async {
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

  test(
    'keeps every generated widget editable through a generic schema',
    () async {
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
    },
  );
}
