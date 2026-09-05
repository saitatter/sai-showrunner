import 'package:flutter_test/flutter_test.dart';

import 'package:showrunner_flutter/plugins/overlays/ui/overlay_widget_config.dart';

void main() {
  test('exposes the canonical overlay widget catalog', () {
    expect(
      overlayWidgetDefinitions.map((definition) => definition.widget),
      containsAll(<String>[
        'label',
        'chatFeed',
        'paidAlert',
        'sceneBanner',
        'shaderLayer',
        'bar',
        'alert',
        'leaderboard',
        'emote-bounce',
      ]),
    );
    expect(findOverlayWidgetDefinition('overlays', 'chatFeed')?.width, 900);
    expect(findOverlayWidgetDefinition('unknown', 'chatFeed'), isNull);
  });

  test('creates defaults compatible with the overlay widget runtime', () {
    final shader = findOverlayWidgetDefinition('overlays', 'shaderLayer')!;
    final config = shader.defaultConfig();
    final widget = shader.createWidget(id: 'shader-1');

    expect(config['preset'], 'aurora');
    expect(config['blendMode'], 'normal');
    expect(widget['id'], 'shader-1');
    expect(widget['plugin'], 'overlays');
    expect((widget['size'] as Map)['height'], 500);
    expect((widget['config'] as Map)['accentColor'], '#9146ff');
  });

  test('keeps supported overlay widgets editable', () {
    final bar = findOverlayWidgetDefinition('overlays', 'bar')!;
    final alert = findOverlayWidgetDefinition('overlays', 'alert')!;
    final leaderboard = findOverlayWidgetDefinition('overlays', 'leaderboard')!;
    final bouncer = findOverlayWidgetDefinition('overlays', 'emote-bounce')!;

    expect(bar.defaultConfig()['direction'], 'Right');
    expect((bar.defaultConfig()['fillStyle'] as Map)['color'], '#00FF00');
    expect(alert.defaultConfig()['textBelowMedia'], true);
    expect(leaderboard.defaultConfig()['sortOrder'], -1);
    expect((bouncer.defaultConfig()['lifeTime'] as Map)['min'], 7);
    expect(bouncer.height, 1080);
  });
}
