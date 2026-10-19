import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema and plugin contracts stay independent from Flutter UI code', () {
    const contractFiles = [
      'lib/schema/data_input.dart',
      'lib/plugins/registry/plugin_contract.dart',
      'lib/plugins/registry/plugin_ui_contract.dart',
    ];

    for (final path in contractFiles) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('package:flutter')),
        reason: '$path must not import Flutter',
      );
      expect(
        source,
        isNot(contains('components/data_inputs')),
        reason: '$path must not depend on the widget input implementation',
      );
    }
  });
}
