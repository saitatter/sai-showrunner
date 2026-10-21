import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_editor_controller.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  OverlayEditorController editor({bool missingId = false}) =>
      OverlayEditorController(
        ResourceData(
          id: 'overlay',
          config: {
            'name': 'Original',
            'size': {'width': 1920, 'height': 1080},
            'future': {'keep': true},
            'widgets': [
              for (final id in ['a', 'b', 'c'])
                {
                  if (!missingId) 'id': id,
                  'name': id,
                  'position': {'x': 0, 'y': 0},
                },
            ],
          },
          state: const {'runtime': 42},
        ),
      );

  test(
    'selection follows identity through reorders and unrelated deletion',
    () {
      final controller = editor();
      addTearDown(controller.dispose);
      controller.selectIndex(1);
      final key = controller.keyAt(1);
      controller.reorder(1, 2);
      expect(controller.selectedIndex, 2);
      controller.deleteWidget(0);
      expect(controller.keyAt(controller.selectedIndex!), key);
      controller.updateWidget(key, {'name': 'Renamed after reordering'});
      expect(controller.widgets[1]['name'], 'Renamed after reordering');
      controller.deleteWidget(1);
      expect(controller.updateWidget(key, {'name': 'Late rename'}), false);
      expect(controller.widgets.single['id'], 'c');
    },
  );

  test('selection and equivalent commands leave authoring clean', () {
    final controller = editor();
    addTearDown(controller.dispose);
    controller.selectIndex(0);
    controller.reorder(0, 0);
    controller.updateWidget(controller.keyAt(0), {'name': 'a'});
    expect(controller.revision, 0);
    expect(controller.canUndo, false);
    expect(controller.dirty, false);
  });

  test('one transform transaction undoes as one semantic change', () {
    final controller = editor();
    addTearDown(controller.dispose);
    final key = controller.keyAt(0);
    controller.beginTransaction();
    for (var x = 1; x <= 20; x++) {
      controller.updateWidget(key, {
        'position': {'x': x, 'y': 0},
      });
    }
    controller.endTransaction();
    expect(controller.dirty, true);
    controller.undo();
    expect(controller.widgets.first['position'], {'x': 0, 'y': 0});
    expect(controller.dirty, false);
    expect(controller.canUndo, false);
    controller.redo();
    expect(controller.widgets.first['position'], {'x': 20, 'y': 0});
    expect(controller.dirty, true);
    expect(controller.resource.config['future'], {'keep': true});
    expect(controller.resource.state, {'runtime': 42});
  });

  test(
    'public snapshots are deeply immutable and caller patches are copied',
    () {
      final controller = editor();
      addTearDown(controller.dispose);
      final position = {'x': 5, 'y': 6};
      controller.updateWidget(controller.keyAt(0), {'position': position});
      position['x'] = 99;
      expect(controller.widgets.first['position'], {'x': 5, 'y': 6});
      expect(
        () => controller.resource.config['name'] = 'mutated',
        throwsUnsupportedError,
      );
      expect(
        () => (controller.widgets.first['position'] as Map)['x'] = 2,
        throwsUnsupportedError,
      );
      expect(() => controller.widgets.clear(), throwsUnsupportedError);
    },
  );

  test(
    'missing shipped layer IDs use stable view keys without persisted aliases',
    () {
      final controller = editor(missingId: true);
      addTearDown(controller.dispose);
      controller.selectIndex(0);
      final key = controller.keyAt(0);
      controller.reorder(0, 2);
      expect(controller.keyAt(controller.selectedIndex!), key);
      expect(
        controller.widgets.every((value) => !value.containsKey('id')),
        true,
      );
      controller.undo();
      expect(controller.keyAt(controller.selectedIndex!), key);
    },
  );

  test(
    'save freezes accepted generation and shares pending ownership',
    () async {
      final controller = editor();
      addTearDown(controller.dispose);
      final key = controller.keyAt(0);
      controller.updateWidget(key, {'name': 'Accepted'});
      final release = Completer<void>();
      ResourceData? saved;
      final saving = controller.save((value) {
        saved = value;
        return release.future;
      });
      final duplicate = controller.save((_) async => fail('duplicate writer'));
      expect(duplicate, same(saving));
      controller.updateWidget(key, {'name': 'Newer draft'});
      await Future<void>.delayed(Duration.zero);
      expect((saved!.config['widgets'] as List).first['name'], 'Accepted');
      release.complete();
      await saving;
      expect(controller.dirty, true);
      expect(controller.saving, false);
      controller.undo();
      expect(controller.dirty, false);
    },
  );

  test('save failure retains history and permits retry', () async {
    final controller = editor();
    addTearDown(controller.dispose);
    controller.updateWidget(controller.keyAt(0), {'name': 'Draft'});
    await expectLater(
      controller.save((_) async => throw StateError('fixture')),
      throwsStateError,
    );
    expect(controller.dirty, true);
    expect(controller.canUndo, true);
    expect(controller.saving, false);
    await controller.save((_) async {});
    expect(controller.dirty, false);
  });

  test('closing a controller ignores delayed save notifications', () async {
    final controller = editor();
    final release = Completer<void>();
    final saving = controller.save((_) => release.future);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    release.complete();
    await saving;
    await expectLater(controller.save((_) async {}), throwsStateError);
  });
}
