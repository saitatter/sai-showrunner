import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/remote/satellite.dart';

void main() {
  Map<String, dynamic> document({List<Map<String, dynamic>>? widgets}) => {
    'name': 'Studio',
    'cloudId': 'private-cloud',
    'ownerId': 'private-owner',
    'remoteTwitchIds': ['private-identity'],
    'accessToken': 'private-token',
    'pages': [
      {
        'id': 'page',
        'sections': [
          {
            'id': 'section',
            'widgets':
                widgets ??
                [
                  {
                    'id': 'button',
                    'plugin': 'remote',
                    'widget': 'button',
                    'config': {
                      'displayName': 'Start',
                      'triggerName': 'start',
                      'color': '#ff0000',
                      'password': 'private-password',
                    },
                  },
                  {
                    'id': 'label',
                    'plugin': 'dashboards',
                    'widget': 'label',
                    'config': {
                      'label': 'Live',
                      'color': '#ffffff',
                      'localPath': r'C:\private\data',
                    },
                  },
                  {
                    'id': 'unknown',
                    'plugin': 'future',
                    'widget': 'future',
                    'config': {'secret': 'private-future'},
                  },
                ],
          },
        ],
      },
    ],
    'resourceSlots': [
      {
        'id': 'slot',
        'name': 'Light',
        'slotType': 'Light',
        'resourceId': 'private-binding',
      },
    ],
  };

  test(
    'public projection retains rendered controls without private authoring fields',
    () {
      final source = document();
      final config = RemoteDashboardConfig.fromJson(source);
      final wire = config.toJson();
      expect(jsonEncode(wire), isNot(contains('private-')));
      final widgets = config.pages.single.sections.single.widgets;
      expect(widgets[0].config['triggerName'], 'start');
      expect(widgets[1].config['label'], 'Live');
      expect(widgets[2].plugin, 'future');
      expect(widgets[2].config, isEmpty);
      expect(config.resourceSlots.single.resourceId, isNull);
      expect(source['accessToken'], 'private-token');
      expect(RemoteDashboardConfig.fromJson(wire).toJson(), wire);
      expect(
        () => widgets.first.config['password'] = 'changed',
        throwsUnsupportedError,
      );
      expect(() => config.pages.clear(), throwsUnsupportedError);
    },
  );

  test('malformed, duplicate and oversized documents fail visibly', () {
    for (final raw in [
      {...document(), 'pages': 'invalid'},
      {...document(), 'name': 42},
      {
        ...document(),
        'pages': List.generate(65, (i) => {'id': 'page-$i'}),
      },
      document(
        widgets: [
          {'id': 42, 'plugin': 'remote', 'widget': 'button'},
        ],
      ),
      document(
        widgets: [
          {
            'id': 'nan',
            'plugin': 'remote',
            'widget': 'button',
            'size': {'width': double.nan},
          },
        ],
      ),
      document(
        widgets: List.generate(
          2,
          (_) => {'id': 'duplicate', 'plugin': 'remote', 'widget': 'button'},
        ),
      ),
      document(
        widgets: List.generate(
          513,
          (i) => {'id': 'widget-$i', 'plugin': 'remote', 'widget': 'button'},
        ),
      ),
      {
        ...document(),
        'pages': List.generate(
          2,
          (p) => {
            'id': 'page-$p',
            'sections': List.generate(129, (i) => {'id': 'section-$p-$i'}),
          },
        ),
      },
      {
        ...document(),
        'pages': List.generate(
          2,
          (p) => {
            'id': 'page-$p',
            'sections': [
              {
                'id': 'section-$p',
                'widgets': List.generate(
                  257,
                  (i) => {
                    'id': 'widget-$p-$i',
                    'plugin': 'remote',
                    'widget': 'button',
                  },
                ),
              },
            ],
          },
        ),
      },
    ]) {
      expect(() => RemoteDashboardConfig.fromJson(raw), throwsFormatException);
    }
  });
}
