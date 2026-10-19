import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/single_instance_lock.dart';

void main() {
  test('allows one owner and releases the lock for the next owner', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-single-instance-',
    );
    addTearDown(() => root.delete(recursive: true));

    final first = await SingleInstanceLock.acquire(root);
    expect(first, isNotNull);
    expect(File(first!.path).existsSync(), isTrue);

    final second = await SingleInstanceLock.acquire(root);
    expect(second, isNull);

    await first.release();
    final third = await SingleInstanceLock.acquire(root);
    expect(third, isNotNull);
    await third!.release();
  });
}
