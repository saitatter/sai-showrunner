import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/editor/sai_nodes/showrunner_clipboard_payload.dart';

void main() {
  test('round-trips host metadata through the sai_nodes extension payload', () {
    const snapshot = ShowRunnerClipboardSnapshot(
      nodeType: 'obs.switchScene',
      data: {
        'plugin': 'obs',
        'nested': {'value': 42},
      },
      title: 'Switch scene',
      isTrigger: true,
    );

    final restored = ShowRunnerClipboardSnapshot.fromJson(snapshot.toJson());

    expect(restored, isNotNull);
    expect(restored!.nodeType, snapshot.nodeType);
    expect(restored.data, snapshot.data);
    expect(restored.title, snapshot.title);
    expect(restored.isVariable, isFalse);
    expect(restored.isTrigger, isTrue);
  });

  test('rejects malformed host metadata', () {
    expect(ShowRunnerClipboardSnapshot.fromJson(null), isNull);
    expect(
      ShowRunnerClipboardSnapshot.fromJson({'nodeType': 'missing-data'}),
      isNull,
    );
  });
}
