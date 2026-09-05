import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/media_picker.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/features/graph/graph_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/schema/stream_plan.dart';

void main() {
  test('resolves plugin resource editor types', () {
    final registry = createDefaultResourceEditorRegistry();

    expect(registry.find('Overlay')?.pluginId, 'showrunner');
    expect(registry.find('Variable')?.displayName, 'Variable');
    expect(registry.find('OBSConnection')?.pluginId, 'obs');
    expect(registry.find('RCONConnection')?.pluginId, 'minecraft');
    expect(registry.find('TTSVoice')?.pluginId, 'sound');
    expect(registry.find('CustomTwitchViewerGroup')?.pluginId, 'twitch');
    expect(registry.find('DiscordWebhook')?.pluginId, 'discord');
    expect(registry.find('BlueSkyAccount')?.pluginId, 'bluesky');
    expect(registry.find('Dashboard')?.pluginId, 'dashboards');
    expect(registry.find('SpellHook')?.pluginId, 'spellcast');
    expect(registry.find('AudioSplitterOutput')?.pluginId, 'sound');
    expect(registry.find('ChannelPointReward')?.pluginId, 'twitch');
    expect(registry.find('Light')?.pluginId, 'iot');
    expect(registry.find('Plug')?.pluginId, 'iot');
    expect(registry.find('StreamPlan')?.pluginId, 'stream-plans');
    expect(registry.find('Unknown'), isNull);
  });

  test('smart device defaults preserve provider routing fields', () {
    final registry = createDefaultResourceEditorRegistry();

    expect(registry.find('Light')!.defaultConfig('Studio bulb'), {
      'name': 'Studio bulb',
      'provider': '',
      'providerId': '',
      'host': '',
      'ip': '',
      'hubKey': '',
      'model': '',
      'resourceType': 'light',
      'target': '',
      'rgbAvailable': true,
      'kelvinAvailable': true,
      'dimmingAvailable': true,
      'transitionsAvailable': true,
    });
    expect(registry.find('Plug')!.defaultConfig('Desk plug'), {
      'name': 'Desk plug',
      'provider': '',
      'providerId': '',
      'host': '',
      'ip': '',
      'model': '',
    });
  });

  testWidgets('smart light editor preserves provider-specific fields', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Light')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'light-1',
        config: {
          'name': 'Desk light',
          'provider': 'govee',
          'providerId': 'AA:BB',
          'model': 'H6001',
          'ip': '192.168.1.20',
          'futureField': 'preserved',
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('Edit smart light'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved!.config['futureField'], 'preserved');
    expect(saved!.config['provider'], 'govee');
    expect(saved!.config['providerId'], 'AA:BB');
    expect(saved!.config['model'], 'H6001');
    expect(saved!.config['ip'], '192.168.1.20');
  });

  test('audio splitter defaults include a valid redirect collection', () {
    final definition = createDefaultResourceEditorRegistry().find(
      'AudioSplitterOutput',
    )!;

    expect(definition.defaultConfig('Main'), {
      'name': 'Main',
      'type': 'splitter',
      'redirects': <Map<String, dynamic>>[],
    });
  });

  test('spellcast defaults include the complete spell configuration', () {
    final definition = createDefaultResourceEditorRegistry().find('SpellHook')!;

    expect(definition.defaultConfig('Raid spell'), {
      'name': 'Raid spell',
      'spellId': '',
      'spellData': {
        'enabled': false,
        'description': '',
        'bits': 10,
        'color': '#719ece',
      },
    });
  });

  test('channel point reward defaults match the Twitch resource schema', () {
    final definition = createDefaultResourceEditorRegistry().find(
      'ChannelPointReward',
    )!;

    expect(definition.defaultConfig('Hydrate'), {
      'name': 'Hydrate',
      'twitchId': '',
      'controllable': true,
      'transient': false,
      'allowEnable': true,
      'rewardData': {
        'prompt': '',
        'backgroundColor': '#9147ff',
        'userInputRequired': false,
        'cost': 100,
        'cooldown': null,
        'maxRedemptionsPerStream': null,
        'maxRedemptionsPerUserPerStream': null,
        'skipQueue': false,
      },
    });
  });

  testWidgets('channel point reward editor preserves nested settings', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find(
      'ChannelPointReward',
    )!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'reward-1',
        config: {
          'name': 'Hydrate',
          'twitchId': 'twitch-reward-1',
          'controllable': true,
          'transient': false,
          'allowEnable': true,
          'rewardData': {
            'prompt': 'Take a sip',
            'backgroundColor': '#22c55e',
            'userInputRequired': true,
            'cost': 500,
            'cooldown': 30,
            'maxRedemptionsPerStream': 10,
            'maxRedemptionsPerUserPerStream': 2,
            'skipQueue': true,
          },
          'futureField': 'preserved',
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('Edit Twitch channel point reward'), findsOneWidget);
    expect(find.text('Require viewer input'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved!.config['futureField'], 'preserved');
    expect(saved!.config['twitchId'], 'twitch-reward-1');
    expect(saved!.config['name'], 'Hydrate');
    expect(saved!.config['rewardData'], {
      'prompt': 'Take a sip',
      'backgroundColor': '#22c55e',
      'userInputRequired': true,
      'cost': 500,
      'cooldown': 30,
      'maxRedemptionsPerStream': 10,
      'maxRedemptionsPerUserPerStream': 2,
      'skipQueue': true,
    });
  });

  testWidgets('spellcast editor persists nested spell settings', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('SpellHook')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'spell-1',
        config: {
          'name': 'Cheer',
          'spellId': 'remote-1',
          'spellData': {
            'enabled': false,
            'description': 'Say hello',
            'bits': 10,
            'color': '#719ece',
          },
          'futureField': 'preserved',
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('Edit Spellcast spell'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved!.config['futureField'], 'preserved');
    expect(saved!.config['spellId'], 'remote-1');
    expect((saved!.config['spellData'] as Map)['enabled'], true);
    expect((saved!.config['spellData'] as Map)['bits'], 10);
  });

  testWidgets('audio splitter editor persists structured output routes', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find(
      'AudioSplitterOutput',
    )!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'splitter-1',
        config: {
          'name': 'Studio outputs',
          'type': 'splitter',
          'redirects': [
            {
              'id': 'main',
              'output': 'system.main',
              'mute': false,
              'volume': 50,
              'keep': true,
            },
            {'id': 'chat', 'output': 'system.chat', 'mute': true, 'volume': 75},
          ],
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('Edit audio splitter'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.byType(Switch), findsNWidgets(2));
    await tester.enterText(
      find.byKey(const ValueKey('audio-split-output-main')),
      'system.default',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Mute audio output').first);
    await tester.tap(find.byTooltip('Delete audio output').last);
    await tester.tap(find.byTooltip('Add audio output'));
    await tester.pump();
    expect(find.byType(Slider), findsNWidgets(2));

    await tester.tap(find.text('Save'));
    await tester.pump();

    final redirects = saved!.config['redirects'] as List;
    expect(saved!.config['type'], 'splitter');
    expect(redirects, hasLength(2));
    expect(redirects.first['mute'], false);
    expect(redirects.first['volume'], 100);
    expect(redirects.first['output'], isNull);
    expect(redirects[1]['output'], 'system.default');
    expect(redirects[1]['mute'], true);
    expect(redirects[1]['volume'], 50);
    expect(redirects[1]['keep'], true);
  });

  testWidgets('dashboard resource editor exposes hierarchical controls', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Dashboard')!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final widget = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(id: 'dashboard-1', config: {'name': 'Studio'}),
      (_) async {},
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

    expect(find.text('Edit dashboard'), findsOneWidget);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.byTooltip('Add page'), findsOneWidget);
  });

  testWidgets('dashboard creation writes complete child defaults', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Dashboard')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(id: 'dashboard-2', config: {'name': 'Studio'}),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    await tester.tap(find.byTooltip('Add page'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add section'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add widget'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();

    final page = (saved!.config['pages'] as List).single as Map;
    final section = (page['sections'] as List).single as Map;
    final widget = (section['widgets'] as List).single as Map;
    expect(page['id'], isNotEmpty);
    expect(section['id'], isNotEmpty);
    expect(section['columns'], 4);
    expect(widget['id'], isNotEmpty);
    expect(widget['plugin'], 'dashboards');
    expect(widget['widget'], 'label');
    expect(widget['size'], {'width': 4, 'height': 1});
    expect(widget['config'], {'label': 'New widget', 'color': '#000000'});
  });

  testWidgets('dashboard editor preserves sharing, slots, and widget config', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Dashboard')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'dashboard-3',
        config: {
          'name': 'Studio',
          'remoteTwitchIds': ['42'],
          'resourceSlots': [
            {
              'id': 'slot-1',
              'name': 'Alert output',
              'slotType': 'SoundOutput',
              'config': {},
            },
          ],
          'pages': [
            {
              'id': 'page-1',
              'name': 'Main',
              'sections': [
                {
                  'id': 'section-1',
                  'name': 'Alerts',
                  'columns': 4,
                  'widgets': [
                    {
                      'id': 'widget-1',
                      'plugin': 'dashboards',
                      'widget': 'label',
                      'size': {'width': 4, 'height': 1},
                      'config': {'label': 'Alert'},
                    },
                  ],
                },
              ],
            },
          ],
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    await tester.tap(find.text('Alert'));
    await tester.pump();
    expect(find.text('Edit dashboard widget'), findsOneWidget);
    final widgetDialog = find.ancestor(
      of: find.text('Edit dashboard widget'),
      matching: find.byType(AlertDialog),
    );
    final widgetSave = find.descendant(
      of: widgetDialog,
      matching: find.widgetWithText(FilledButton, 'Save'),
    );
    await tester.ensureVisible(widgetSave);
    await tester.tap(widgetSave);
    await tester.pump();
    final editorSave = find.widgetWithText(FilledButton, 'Save').last;
    await tester.ensureVisible(editorSave);
    await tester.tap(editorSave);
    await tester.pumpAndSettle();

    expect(saved!.config['remoteTwitchIds'], ['42']);
    expect(saved!.config['resourceSlots'], hasLength(1));
    final page = (saved!.config['pages'] as List).single as Map;
    final section = (page['sections'] as List).single as Map;
    final widget = (section['widgets'] as List).single as Map;
    expect(widget['config'], {'label': 'Alert'});
  });

  testWidgets('dashboard widget editor reports invalid config JSON', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Dashboard')!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'dashboard-invalid-json',
        config: {
          'name': 'Studio',
          'pages': [
            {
              'id': 'page-1',
              'name': 'Main',
              'sections': [
                {
                  'id': 'section-1',
                  'name': 'Alerts',
                  'widgets': [
                    {
                      'id': 'widget-1',
                      'plugin': 'dashboards',
                      'widget': 'label',
                      'config': {'label': 'Alert'},
                    },
                  ],
                },
              ],
            },
          ],
        },
      ),
      (_) async {},
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    await tester.tap(find.text('Alert'));
    await tester.pump();
    final widgetDialog = find.ancestor(
      of: find.text('Edit dashboard widget'),
      matching: find.byType(AlertDialog),
    );
    final configField = find.descendant(
      of: widgetDialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(configField.last, '{invalid');
    final save = find.descendant(
      of: widgetDialog,
      matching: find.widgetWithText(FilledButton, 'Save'),
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();

    expect(find.text('Widget config must be valid JSON.'), findsOneWidget);
    expect(find.text('Edit dashboard widget'), findsOneWidget);
  });

  test('dashboard defaults include the persisted hierarchy fields', () {
    final definition = createDefaultResourceEditorRegistry().find('Dashboard')!;
    final defaults = definition.defaultConfig('Studio');

    expect(defaults, {
      'name': 'Studio',
      'pages': <Map<String, dynamic>>[],
      'remoteTwitchIds': <String>[],
      'resourceSlots': <Map<String, dynamic>>[],
    });
  });

  testWidgets('overlay editor exposes typed widget and media controls', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Overlay')!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'overlay-1',
        config: {
          'name': 'Media overlay',
          'widgets': [
            {'type': 'image', 'media': 'existing.png'},
          ],
        },
      ),
      (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaPickerScope(directory: Directory('unused'), child: editor),
        ),
      ),
    );

    expect(find.text('Edit overlay'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
    expect(find.byTooltip('Select media'), findsOneWidget);
  });

  testWidgets('overlay editor preserves canonical widget resources', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Overlay')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'overlay-canonical',
        config: {
          'name': 'Canonical overlay',
          'size': {'width': 1280, 'height': 720},
          'widgets': [
            {
              'id': 'widget-1',
              'plugin': 'overlays',
              'widget': 'shaderLayer',
              'name': 'Background',
              'position': {'x': 12, 'y': 24},
              'size': {'width': 900, 'height': 500},
              'config': {'preset': 'aurora', 'speed': 1},
              'visible': true,
              'locked': false,
            },
          ],
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('Plugin'), findsOneWidget);
    expect(find.text('Shader Preset'), findsOneWidget);
    expect(find.text('Shader Graph (JSON)'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved?.config['size'], {'width': 1280, 'height': 720});
    final widget = (saved?.config['widgets'] as List).single as Map;
    expect(widget['plugin'], 'overlays');
    expect(widget['widget'], 'shaderLayer');
    expect(widget['position'], {'x': 12, 'y': 24});
    expect(widget['config'], {'preset': 'aurora', 'speed': 1});
  });

  testWidgets('overlay editor adds a canonical widget from the catalog', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find('Overlay')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'overlay-catalog',
        config: {'name': 'Catalog overlay', 'widgets': []},
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    await tester.tap(find.byTooltip('Add widget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat Feed'));
    await tester.pumpAndSettle();

    expect(find.text('Font Family'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final widget = (saved?.config['widgets'] as List).single as Map;
    expect(widget['plugin'], 'overlays');
    expect(widget['widget'], 'chatFeed');
    expect((widget['config'] as Map)['maxMessages'], 8);
  });

  testWidgets('stream plan editor adds and persists ordered segments', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find(
      'StreamPlan',
    )!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'plan-1',
        config: {'name': 'Friday show', 'segments': []},
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('Edit stream plan'), findsOneWidget);
    expect(find.text('No segments defined.'), findsOneWidget);
    await tester.tap(find.byTooltip('Add segment'));
    await tester.pump();
    expect(find.text('Segment 1'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.config['segments'], hasLength(1));
    expect((saved!.config['segments'] as List).single['name'], 'New segment');
  });

  testWidgets('stream plan segment editor persists Twitch tags', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find(
      'StreamPlan',
    )!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      ResourceData(
        id: 'plan-tags',
        config: {
          'name': 'Tagged show',
          'segments': [
            {
              'id': 'segment-1',
              'name': 'Intro',
              'components': {
                'twitch-stream-info': {
                  'title': 'Welcome',
                  'category': 'Just Chatting',
                  'tags': ['hello', 'showrunner'],
                },
              },
            },
          ],
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('Tags (comma separated)'), findsOneWidget);
    final tagsField = find.ancestor(
      of: find.text('Tags (comma separated)'),
      matching: find.byType(TextFormField),
    );
    expect(tagsField, findsOneWidget);
    await tester.enterText(tagsField, 'hello, flutter');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      ((saved!.config['segments'] as List).single['components']
          as Map)['twitch-stream-info']['tags'],
      ['hello', 'flutter'],
    );
  });

  testWidgets('runtime stream plan editor exposes transition graphs', (
    tester,
  ) async {
    final definition = createDefaultResourceEditorRegistry().find(
      'StreamPlan',
    )!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.runtimeBuilder!(
      tester.element(find.byType(Scaffold)),
      ResourceData(
        id: 'plan-runtime',
        config: {
          'name': 'Runtime plan',
          'segments': [
            {
              'id': 'segment-runtime',
              'name': 'Intro',
              'components': const <String, dynamic>{},
              'activationAutomation': emptyInlineAutomation(),
              'deactivationAutomation': emptyInlineAutomation(),
            },
          ],
        },
      ),
      (_) async {},
      registryFuture: Future.value(DartPluginRegistry()),
      resourceOptionsLoader: (_) async => const [],
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
    await tester.pump();

    expect(find.text('On Activate'), findsNWidgets(2));
    expect(find.text('On Deactivate'), findsNWidgets(2));
    expect(find.text('Segment 1'), findsOneWidget);
    expect(find.byType(ShowRunnerInlineGraphEditor), findsNothing);
    await tester.tap(find.byKey(const ValueKey('stream-plan-On Activate')));
    final segmentActivation = find.byKey(
      const ValueKey('stream-plan-segment-segment-runtime-On Activate'),
    );
    await tester.ensureVisible(segmentActivation);
    await tester.tap(segmentActivation);
    await tester.pump();
    expect(find.byType(ShowRunnerInlineGraphEditor), findsNWidgets(2));
  });

  testWidgets('variable editor persists the persistent toggle', (tester) async {
    final definition = createDefaultResourceEditorRegistry().find('Variable')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'variable-1',
        config: {'name': 'Counter', 'type': 'number', 'persistent': true},
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved?.config['persistent'], false);
  });

  test('serializes overlay and variable resources', () {
    const resource = ResourceData(
      id: 'overlay-1',
      config: {'name': 'Alert Overlay', 'width': 1920, 'height': 1080},
      state: {'active': true},
    );
    final restored = ResourceData.fromJson(resource.toJson());

    expect(restored.id, 'overlay-1');
    expect(restored.name, 'Alert Overlay');

    final overlay = OverlayResource.fromResource(resource);
    expect(overlay.width, 1920);
    expect(overlay.height, 1080);

    const varResource = ResourceData(
      id: 'var-1',
      config: {'name': 'FollowerCount', 'type': 'number', 'defaultValue': 0},
      state: {'value': 42},
    );
    final variable = VariableResource.fromResource(varResource);
    expect(variable.name, 'FollowerCount');
    expect(variable.currentValue, 42);
  });
}
