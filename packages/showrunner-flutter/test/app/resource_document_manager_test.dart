import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/resource_document_manager.dart';
import 'package:showrunner_flutter/features/resources/overlay/overlay_document.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  test(
    'saving advances the storage baseline without discarding newer edits',
    () {
      final manager = ResourceDocumentManager();
      const original = ResourceData(
        id: 'overlay',
        config: {'name': 'Original'},
      );
      const saved = ResourceData(id: 'overlay', config: {'name': 'Saved'});
      const newer = ResourceData(id: 'overlay', config: {'name': 'Newer'});
      manager.open(original);
      final baseline = manager.storageRevisions['overlay'];
      manager.update(saved, isDirty: true);
      manager.update(newer, isDirty: true);
      manager.acceptPersisted(saved, baseline);
      manager.markSavedIfCurrent(saved, saved);
      expect(manager.storageRevisions['overlay'], isNot(baseline));
      expect(manager.resources['overlay'], same(newer));
      expect(manager.hasUnsavedChanges, isTrue);
      manager.close('overlay');
      manager.open(original);
      final reopened = manager.storageRevisions['overlay'];
      manager.acceptPersisted(saved, baseline);
      expect(manager.storageRevisions['overlay'], same(reopened));
      manager.close('overlay');
      expect(manager.storageRevisions, isEmpty);
    },
  );

  test(
    'existing canvas-sized widgets are repaired using their overlay size',
    () {
      const source = ResourceData(
        id: 'overlay',
        config: {
          'name': 'Vertical',
          'size': {'width': 1080, 'height': 1920},
          'widgets': [
            {
              'id': 'emotes',
              'size': {'width': 'canvas', 'height': 'canvas'},
            },
          ],
        },
      );
      final widgets = OverlayDocument(source).initialWidgets;
      expect(widgets.single['size'], {'width': 1080, 'height': 1920});
      expect(
        (source.config['widgets'] as List).single['size']['width'],
        'canvas',
      );
    },
  );
  test('save completion keeps newer edits and closed documents intact', () {
    final manager = ResourceDocumentManager();
    const first = ResourceData(id: 'overlay', config: {'name': 'First'});
    const second = ResourceData(id: 'overlay', config: {'name': 'Second'});
    manager.update(first, isDirty: true);
    manager.update(second, isDirty: true);
    manager.markSavedIfCurrent(first, first);
    expect(manager.resources['overlay'], same(second));
    expect(manager.hasUnsavedChanges, isTrue);
    manager.markSavedIfCurrent(second, second);
    expect(manager.hasUnsavedChanges, isFalse);
    manager.close('overlay');
    manager.markSavedIfCurrent(second, second);
    expect(manager.resources, isEmpty);
    expect(manager.dirty, isEmpty);
  });
  test('closing other documents discards their snapshots and dirty state', () {
    final manager = ResourceDocumentManager();
    const retained = ResourceData(id: 'retained', config: {'name': 'Retained'});
    const discarded = ResourceData(id: 'discarded', config: {'name': 'Edited'});
    manager.update(retained, isDirty: true);
    manager.update(discarded, isDirty: true);
    manager.retainOnly(retained.id);
    expect(manager.resources, {'retained': retained});
    expect(manager.dirty, {'retained': true});
    manager.markSaved(retained);
    expect(manager.hasUnsavedChanges, isFalse);
    manager.retainOnly(null);
    expect(manager.resources, isEmpty);
    expect(manager.dirty, isEmpty);
  });
  test(
    'reopening a resource keeps its dirty snapshot until it is saved or closed',
    () {
      final manager = ResourceDocumentManager();
      const loaded = ResourceData(id: 'overlay', config: {'name': 'Loaded'});
      const edited = ResourceData(
        id: 'overlay',
        config: {'name': 'Edited'},
        state: {'value': 42},
      );
      manager.open(loaded);
      manager.update(edited, isDirty: true);
      manager.open(loaded);
      expect(manager.resources['overlay'], same(edited));
      expect(manager.hasUnsavedChanges, isTrue);
      manager.markSaved(edited);
      expect(manager.hasUnsavedChanges, isFalse);
      manager.close('overlay');
      expect(manager.resources, isEmpty);
      expect(manager.dirty, isEmpty);
    },
  );
  test(
    'overlay snapshots preserve state and unknown fields without sharing editable JSON',
    () {
      final source = ResourceData(
        id: 'overlay',
        config: {
          'name': 'Original',
          'custom': 'preserved',
          'size': {'width': 1920, 'height': 1080},
          'widgets': [
            {
              'id': 'label',
              'plugin': 'overlays',
              'widget': 'label',
              'config': {'message': 'Original'},
            },
          ],
        },
        state: {'value': 42},
      );
      final document = OverlayDocument(source);
      final widgets = document.initialWidgets;
      (widgets.first['config'] as Map)['message'] = 'Edited';
      final snapshot = document.snapshot(
        name: 'Edited',
        width: 1920,
        height: 1080,
        widgets: widgets,
      );
      (widgets.first['config'] as Map)['message'] = 'Later';
      expect(
        ((source.config['widgets'] as List).first['config'] as Map)['message'],
        'Original',
      );
      expect(
        ((snapshot.config['widgets'] as List).first['config']
            as Map)['message'],
        'Edited',
      );
      expect(snapshot.config['custom'], 'preserved');
      expect(snapshot.state['value'], 42);
    },
  );
}
