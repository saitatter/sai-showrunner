import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_module.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registration.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

PluginModuleRegistration entry(
  String id, {
  List<String> requires = const [],
  List<String> optional = const [],
  DartPluginManifest? manifest,
  List<String>? events,
  int version = 1,
}) => PluginModuleRegistration(
  id: PluginId(id),
  module: ManifestDartPluginModule(
    manifest ?? DartPluginManifest(id: PluginId(id), name: id),
    onStart: () async => events?.add('start:$id'),
    onStop: () async => events?.add('stop:$id'),
  ),
  dependencies: requires.map(PluginId.new),
  optionalDependencies: optional.map(PluginId.new),
  contractVersion: version,
);

void main() {
  test('a bad last module leaves the entire pack unregistered', () async {
    final registry = DartPluginRegistry();
    var notifications = 0;
    registry.addListener(() => notifications++);
    expect(
      () => registry.registerModules([
        entry('valid'),
        entry(
          'invalid',
          manifest: DartPluginManifest(
            id: const PluginId('invalid'),
            name: 'Invalid',
            resources: [
              ResourceSpec(
                ownerId: const PluginId('wrong-owner'),
                resourceTypeId: const ResourceTypeId('Example'),
                displayName: 'Example',
                storageDirectory: 'examples',
                defaultConfigFactory: (name) => {'name': name},
              ),
            ],
          ),
        ),
      ]),
      throwsArgumentError,
    );
    expect(registry.plugins, isEmpty);
    expect(registry.findResource('Example'), isNull);
    expect(notifications, 0);
    await registry.close();
  });

  test(
    'composition preserves runtime states and notifies once per pack',
    () async {
      final registry = DartPluginRegistry()
        ..registerModules([entry('existing')]);
      registry.updateDynamicState('existing', 'counter', 42);
      var notifications = 0;
      registry.addListener(() => notifications++);
      expect(
        () => registry.registerModules([entry('new'), entry('existing')]),
        throwsArgumentError,
      );
      expect(registry.findPlugin('new'), isNull);
      expect(registry.stateValues('existing'), {'counter': 42});
      registry.registerModules([entry('first'), entry('second')]);
      expect(registry.stateValues('existing'), {'counter': 42});
      expect(notifications, 1);
      await registry.close();
    },
  );

  test(
    'dependencies start first and stop last; startup seals composition',
    () async {
      final events = <String>[];
      final registry = DartPluginRegistry()
        ..registerModules([
          entry('consumer', requires: ['provider'], events: events),
          entry('provider', events: events),
          entry('independent', optional: ['absent'], events: events),
        ]);
      await registry.initialize();
      expect(() => registry.registerModules([entry('late')]), throwsStateError);
      await registry.start();
      await registry.close();
      expect(events, [
        'start:provider',
        'start:consumer',
        'start:independent',
        'stop:independent',
        'stop:consumer',
        'stop:provider',
      ]);
    },
  );

  test(
    'rejects missing dependencies, cycles, wrong IDs and versions atomically',
    () async {
      final cases = <List<PluginModuleRegistration>>[
        [
          entry('one', requires: ['missing']),
        ],
        [
          entry('one', requires: ['two']),
          entry('two', requires: ['one']),
        ],
        [
          entry('one', optional: ['two']),
          entry('two', requires: ['one']),
        ],
        [
          entry('one', requires: ['one']),
        ],
        [entry('one', version: 2)],
        [
          entry(
            'one',
            manifest: const DartPluginManifest(
              id: PluginId('other'),
              name: 'Other',
            ),
          ),
        ],
        [entry(' ')],
      ];
      for (final invalid in cases) {
        final registry = DartPluginRegistry()..registerModules([entry('kept')]);
        expect(() => registry.registerModules(invalid), throwsArgumentError);
        expect(registry.plugins.map((plugin) => plugin.id.value), ['kept']);
        await registry.close();
      }
    },
  );

  test(
    'resource editor coverage is validated before registering a pack',
    () async {
      final registry = DartPluginRegistry();
      final module = entry(
        'resources',
        manifest: DartPluginManifest(
          id: const PluginId('resources'),
          name: 'Resources',
          resources: [
            ResourceSpec(
              ownerId: const PluginId('resources'),
              resourceTypeId: const ResourceTypeId('Example'),
              displayName: 'Example',
              storageDirectory: 'examples',
              defaultConfigFactory: (name) => {'name': name},
            ),
          ],
        ),
      );
      expect(
        () => registry.registerModules([module], availableEditors: {}),
        throwsArgumentError,
      );
      expect(registry.plugins, isEmpty);
      registry.registerModules(
        [module],
        availableEditors: {const ResourceTypeId('Example')},
      );
      expect(registry.findResource('Example'), isNotNull);
      await registry.close();
    },
  );

  test(
    'typed factory copies dependency metadata and receives its concrete context',
    () {
      final dependencies = <PluginId>[const PluginId('base')];
      final factory = FirstPartyPluginContribution<String>(
        id: const PluginId('sample'),
        dependencies: dependencies,
        createModule: (name) => ManifestDartPluginModule(
          DartPluginManifest(id: const PluginId('sample'), name: name),
        ),
      );
      dependencies.clear();
      final registration = factory.create('Typed context');
      expect(registration.module.manifest.name, 'Typed context');
      expect(registration.dependencies, {const PluginId('base')});
      expect(() => registration.dependencies.clear(), throwsUnsupportedError);
    },
  );
}
