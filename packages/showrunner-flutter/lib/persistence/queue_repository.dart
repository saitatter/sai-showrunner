import 'dart:convert';
import 'dart:io';

import 'filesystem/atomic_file.dart';
import '../runtime/action_queue.dart';

final class QueueRepository {
  const QueueRepository(this.file);

  final File file;

  Future<void> save(DartActionQueue queue) async {
    await writeAtomicText(
      file,
      const JsonEncoder.withIndent('  ').convert(queue.toJson()),
    );
  }

  Future<void> load(DartActionQueue queue) async {
    if (!await file.exists()) return;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map) {
      throw const FormatException('Queue persistence must contain an object.');
    }
    queue.restore(Map<String, dynamic>.from(value));
  }
}
