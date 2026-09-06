import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/editor/sai_nodes/showrunner_clipboard_payload.dart';

void main() {
  ShowRunnerClipboardSnapshot snapshot(String id) =>
      ShowRunnerClipboardSnapshot(nodeType: id, data: {'id': id});

  test('keeps host metadata bounded and returns immutable lists', () {
    final store = ShowRunnerClipboardPayloadStore(maxEntries: 2);

    store.remember('one', [snapshot('one')]);
    store.remember('two', [snapshot('two')]);
    store.remember('three', [snapshot('three')]);

    expect(store.snapshotsFor('one'), isNull);
    expect(store.snapshotsFor('two')!.single.nodeType, 'two');
    expect(
      () => store.snapshotsFor('two')!.add(snapshot('invalid')),
      throwsUnsupportedError,
    );
  });

  test('ignores empty payloads and empty metadata', () {
    final store = ShowRunnerClipboardPayloadStore();

    store.remember('', [snapshot('ignored')]);
    store.remember('empty', const []);

    expect(store.snapshotsFor(''), isNull);
    expect(store.snapshotsFor('empty'), isNull);
  });
}
