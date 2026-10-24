import 'package:showrunner_flutter/services/public_data_projection.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_projection_policy.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

OverlayProjectionPolicy policy(List<Map<String, dynamic>> widgets) =>
    OverlayProjectionPolicy.fromResource(
      ResourceData(id: 'fixture', config: {'widgets': widgets}),
    );

void main() {
  test('unrelated and unknown widgets do not grant state or viewer access', () {
    final projection = policy([
      {'plugin': 'overlays', 'widget': 'label', 'config': {}},
      {
        'plugin': 'unknown',
        'widget': 'shaderLayer',
        'config': {
          'shaderUniformBindings': {
            'u': {
              'source': 'state',
              'plugin': 'private',
              'state': 'account',
              'path': '',
            },
          },
        },
      },
    ]);
    expect(projection.viewerData, isFalse);
    expect(projection.statePaths, isEmpty);
    expect(
      projection.projectState('private', 'account', {
        'password': 'private-marker',
      }),
      isNull,
    );
  });

  test('installed heart rate widgets project only declared public fields', () {
    final projection = policy([
      {'plugin': 'heartrate', 'widget': 'heartRate', 'config': {}},
    ]);
    expect(
      projection.projectState('heartrate', 'heartRate', {
        'bpm': 80,
        'stale': false,
        'accessToken': 'private-marker',
        'devicePath': r'C:\private',
      }),
      {'bpm': 80, 'stale': false},
    );
    expect(
      projection.projectState('heartrate', 'device', {
        'connected': true,
        'batteryPercent': 75,
        'deviceId': 'private-device-id',
      }),
      {'connected': true, 'batteryPercent': 75},
    );
    expect(
      projection.projectState('twitch', 'account', {
        'accessToken': 'private-marker',
      }),
      isNull,
    );
  });

  test(
    'shader bindings share selected nested paths rather than provider maps',
    () {
      final projection = policy([
        {
          'plugin': 'overlays',
          'widget': 'shaderLayer',
          'config': {
            'shaderUniformBindings': {
              'u_bpm': {
                'source': 'state',
                'plugin': 'probe',
                'state': 'metrics',
                'path': 'measurements.bpm',
              },
              'u_private': {
                'source': 'state',
                'plugin': 'probe',
                'state': 'credentials',
                'path': 'accessToken',
              },
            },
          },
        },
      ]);
      expect(
        projection.projectState('probe', 'metrics', {
          'measurements': {'bpm': 91, 'secret': 'private-marker'},
          'accessToken': 'private-marker',
        }),
        {
          'measurements': {'bpm': 91},
        },
      );
      expect(
        projection.statePaths.containsKey('probe\u0000credentials'),
        isFalse,
      );
    },
  );

  test(
    'leaderboards expose selected values and stable public identity fields',
    () {
      final projection = policy([
        {
          'plugin': 'overlays',
          'widget': 'leaderboard',
          'config': {
            'variables': [
              {'variable': 'score'},
              {'variable': 'details'},
              {'variable': 'accessToken'},
            ],
          },
        },
      ]);
      final row = projection.projectViewer(
        const ViewerDataRow(
          provider: 'youtube',
          viewer: ViewerIdentity(id: 'one', displayName: 'Viewer'),
          values: {
            'score': 10,
            'accessToken': 'private-marker',
            'privateNote': 'private-marker',
            'details': {
              'label': 'public',
              'password': 'private-marker',
              'filePath': r'C:\private',
            },
          },
        ),
      );
      expect(row['score'], 10);
      expect(row['youtube'], 'one');
      expect(row['youtube_name'], 'Viewer');
      expect(row['details'], {'label': 'public'});
      expect(jsonEncode(row), isNot(contains('private-marker')));
    },
  );

  test(
    'public value projection bounds cycles and removes local paths/non-finite values',
    () {
      for (final path in [
        r'C:\Users\fixture\private',
        r'\\host\share\private',
        '/home/fixture/private',
        'file:///fixture/private',
      ]) {
        expect(projectPublicValue(path), isNull, reason: path);
      }
      expect(projectPublicValue(double.infinity), isNull);
      expect(
        projectPublicValue('https://example.test/public'),
        'https://example.test/public',
      );
      final cycle = <String, dynamic>{};
      for (var index = 0; index < 64; index++) {
        cycle['item$index'] = cycle;
      }
      expect(
        utf8.encode(jsonEncode(projectPublicValue(cycle))).length,
        lessThan(32768),
      );
    },
  );
}
