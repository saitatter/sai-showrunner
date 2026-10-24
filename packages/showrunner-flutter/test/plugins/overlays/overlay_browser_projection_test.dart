import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_browser_projection.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_media_resources.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  const media = OverlayMediaResources();
  ResourceData resource(
    List<Map<String, dynamic>> widgets, {
    int width = 1920,
  }) => ResourceData(
    id: 'fixture',
    config: {
      'name': 'Fixture',
      'size': {'width': width, 'height': 1080},
      'widgets': widgets,
    },
  );
  test(
    'browser render DTO excludes authoring graphs, unknown config and nested credentials',
    () async {
      final source = resource([
        {
          'id': 'label',
          'plugin': 'overlays',
          'widget': 'label',
          'config': {
            'message': 'Visible',
            'accessToken': 'private-marker',
            'font': {'fontSize': 24, 'password': 'private-marker'},
          },
        },
        {
          'id': 'shader',
          'plugin': 'overlays',
          'widget': 'shaderLayer',
          'config': {
            'preset': 'custom',
            'customFragmentShader': 'void main() {}',
            'shaderGraph': {'private': 'authoring-marker'},
          },
        },
      ]);
      final projected = await projectOverlayConfig(source, media);
      final encoded = jsonEncode(projected);
      expect(encoded, contains('Visible'));
      expect(encoded, contains('void main() {}'));
      expect(encoded, isNot(contains('private-marker')));
      expect(encoded, isNot(contains('authoring-marker')));
      expect(encoded, isNot(contains('shaderGraph')));
      expect(jsonEncode(source.config), contains('authoring-marker'));
    },
  );

  test(
    'rejects duplicate IDs and resource limits before browser allocation',
    () async {
      final label = <String, dynamic>{
        'id': 'same',
        'plugin': 'overlays',
        'widget': 'label',
        'config': {},
      };
      await expectLater(
        projectOverlayConfig(resource([label, label]), media),
        throwsFormatException,
      );
      await expectLater(
        projectOverlayConfig(resource([], width: 9000), media),
        throwsFormatException,
      );
      await expectLater(
        projectOverlayConfig(
          resource([
            for (var index = 0; index < 9; index++)
              {
                'id': 'shader$index',
                'plugin': 'overlays',
                'widget': 'shaderLayer',
                'config': {},
              },
          ]),
          media,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'projects only contained media URLs and rejects Windows junction escapes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'overlay-media-scope-',
      );
      addTearDown(() => root.delete(recursive: true));
      final allowed = await Directory('${root.path}/media').create();
      final outside = await Directory('${root.path}/outside').create();
      final file = File('${allowed.path}/inside fixture.wav');
      await file.writeAsBytes([1, 2, 3]);
      final private = File('${outside.path}/private.wav');
      await private.writeAsBytes([4, 5, 6]);
      final resolver = OverlayMediaResources(mediaRoot: allowed);
      expect(
        await resolver.browserUrl(file.path, 'fixture'),
        '/overlays/fixture/media/default/inside%20fixture.wav',
      );
      expect(await resolver.browserUrl(private.path, 'fixture'), isNull);
      final config = await projectOverlayConfig(
        resource([
          {
            'id': 'alert',
            'plugin': 'overlays',
            'widget': 'alert',
            'config': {'media': file.path},
          },
        ]),
        resolver,
      );
      expect(
        jsonEncode(config),
        contains('/overlays/fixture/media/default/inside%20fixture.wav'),
      );
      expect(jsonEncode(config), isNot(contains(root.path)));
      if (Platform.isWindows) {
        final junction = '${allowed.path}/redirect';
        final result = await Process.run('powershell.exe', [
          '-NoProfile',
          '-Command',
          "New-Item -ItemType Junction -Path '${junction.replaceAll("'", "''")}' -Target '${outside.path.replaceAll("'", "''")}' | Out-Null",
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          await resolver.browserUrl('$junction/private.wav', 'fixture'),
          isNull,
        );
        await expectLater(
          resolver.fileFor('default', ['redirect', 'private.wav']),
          throwsArgumentError,
        );
      }
      expect(await private.readAsBytes(), [4, 5, 6]);
    },
  );
}
