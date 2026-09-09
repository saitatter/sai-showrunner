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
}
