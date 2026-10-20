import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _directives = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');

void main() {
  test(
    'provider manifests and workers do not import widget libraries or screens',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib/plugins',
      ).listSync(recursive: true).whereType<File>()) {
        final path = file.path.replaceAll('\\', '/');
        final name = path.split('/').last;
        if (name != 'manifest.dart' &&
            name != 'resources.dart' &&
            !name.endsWith('runtime.dart') &&
            !name.endsWith('worker.dart')) {
          continue;
        }
        for (final directive in _directives.allMatches(
          file.readAsStringSync(),
        )) {
          final uri = directive[1]!;
          if (RegExp(
                r'package:flutter/(material|widgets|cupertino)\.dart',
              ).hasMatch(uri) ||
              uri.contains('/features/') ||
              uri.contains('/ui/')) {
            violations.add('$path imports $uri');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'composition imports provider factories instead of concrete transports or screens',
    () {
      for (final name in [
        'plugin_bootstrap.dart',
        'configured_plugin_registrar.dart',
        'default_plugin_registrar.dart',
      ]) {
        final file = File('lib/plugins/registry/$name');
        final uris = _directives
            .allMatches(file.readAsStringSync())
            .map((match) => match[1]!);
        expect(
          uris.where(
            (uri) =>
                uri.contains('/ui/') ||
                uri.endsWith('/actions.dart') ||
                uri.endsWith('/connection_router.dart') ||
                uri.endsWith('/http_provider_transports.dart') ||
                uri.endsWith('/account_runtime.dart'),
          ),
          isEmpty,
          reason: '$name must compose provider-owned factories',
        );
        expect(file.readAsStringSync(), isNot(contains("part '")));
      }
    },
  );

  test(
    'provider factories never depend on the universal application bootstrap',
    () {
      for (final file in Directory(
        'lib/plugins',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.replaceAll('\\', '/').endsWith('/bootstrap.dart')) {
          continue;
        }
        expect(
          _directives
              .allMatches(file.readAsStringSync())
              .map((match) => match[1]!)
              .where(
                (uri) =>
                    uri.endsWith('plugin_bootstrap.dart') ||
                    uri.endsWith('_plugin_registrar.dart'),
              ),
          isEmpty,
          reason: file.path,
        );
      }
    },
  );
}
