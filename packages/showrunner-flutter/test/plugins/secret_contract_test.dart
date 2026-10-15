import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';

void main() {
  test('all manifest secret settings use protected persistence', () {
    final registry = createDefaultPluginRegistry();
    addTearDown(registry.dispose);
    for (final plugin in registry.plugins) {
      final protected = secretSettingIdsFor(plugin.id.value);
      for (final setting in plugin.settings.where(
        (setting) => setting.secret,
      )) {
        expect(
          protected,
          contains(setting.id.value),
          reason: '${plugin.id}.${setting.id} must use secret storage',
        );
      }
    }
  });
}
