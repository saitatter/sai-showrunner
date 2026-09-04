import 'dart:convert';
import 'dart:io';

import '../runtime/action_queue.dart';

final class QueueRepository {
  const QueueRepository(this.file);

  final File file;

  Future<void> save(DartActionQueue queue) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(queue.toJson()),
    );
    await temporary.rename(file.path);
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
