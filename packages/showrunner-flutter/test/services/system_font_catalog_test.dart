import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/system_font_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('font-catalog-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('loads installed fonts once and excludes vertical aliases', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listFontFamilies');
      calls++;
      return ['Segoe UI', '@Segoe UI', 'Arial', 'Arial', ''];
    });
    final catalog = SystemFontCatalog(channel: channel);
    expect(await catalog.load(), ['Arial', 'Inter var', 'Segoe UI']);
    await catalog.load();
    expect(calls, 1);
  });

  test(
    'selector remains available when native enumeration is unavailable',
    () async {
      final catalog = SystemFontCatalog(channel: channel);
      expect(
        await catalog.load(),
        containsAll(['Arial', 'Impact', 'Inter var']),
      );
    },
  );
}
