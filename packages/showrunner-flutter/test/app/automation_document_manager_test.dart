import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/automation_document_manager.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('opens each automation once and keeps the active document', () {
    final manager = AutomationDocumentManager();
    const first = AutomationData(extra: {'name': 'First'});
    const second = AutomationData(extra: {'name': 'Second'});

    final firstSession = manager.open(first, 'first.yaml');
    manager.open(second, 'second.yaml');
    final reopened = manager.open(
      const AutomationData(extra: {'name': 'Changed on disk'}),
      'first.yaml',
    );

    expect(manager.documents.map((document) => document.fileName), [
      'first.yaml',
      'second.yaml',
    ]);
    expect(manager.activeFileName, 'first.yaml');
    expect(identical(reopened, firstSession), isTrue);
    expect(reopened.data.extra['name'], 'First');
  });

  test('retains dirty edits while switching and syncs saved data', () {
    final manager = AutomationDocumentManager();
    manager.open(const AutomationData(extra: {'version': 1}), 'first.yaml');
    manager.setActiveDirty(true);
    manager.updateActive(const AutomationData(extra: {'version': 2}));
    manager.open(const AutomationData(extra: {'version': 3}), 'second.yaml');

    expect(manager.activate('first.yaml'), isTrue);
    expect(manager.active!.data.extra['version'], 2);
    expect(manager.active!.dirty, isTrue);

    manager.markActiveSaved(const AutomationData(extra: {'version': 2}));
    expect(manager.active!.dirty, isFalse);
    expect(manager.hasDirtyDocuments, isFalse);
  });

  test('closing an active document selects its predecessor', () {
    final manager = AutomationDocumentManager();
    manager.open(const AutomationData(), 'a.yaml');
    manager.open(const AutomationData(), 'b.yaml');
    manager.open(const AutomationData(), 'c.yaml');
    manager.activate('b.yaml');

    expect(manager.close('b.yaml'), isTrue);
    expect(manager.activeFileName, 'a.yaml');
    expect(manager.close('a.yaml'), isTrue);
    expect(manager.activeFileName, 'c.yaml');
    expect(manager.close('c.yaml'), isTrue);
    expect(manager.activeFileName, isNull);
    expect(manager.close('missing.yaml'), isFalse);
  });

  test('serializes open order and selected automation', () {
    final manager = AutomationDocumentManager();
    manager.open(const AutomationData(), 'b.yaml');
    manager.open(const AutomationData(), 'a.yaml');
    manager.activate('b.yaml');

    expect(manager.toSettings(), {
      'openAutomationTabs': ['b.yaml', 'a.yaml'],
      'selectedAutomationTab': 'b.yaml',
    });
  });
}
