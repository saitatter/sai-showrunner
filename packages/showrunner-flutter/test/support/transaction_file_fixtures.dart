import 'dart:io';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';

final class FaultInjectingFiles extends TransactionFileOperations {
  FaultInjectingFiles({this.writeAt, this.removeAt, this.after = false});
  final int? writeAt, removeAt;
  final bool after;
  int writes = 0, removes = 0;
  @override
  Future<void> write(File file, List<int> bytes) async {
    final fail = ++writes == writeAt;
    if (fail && !after) {
      throw const FileSystemException('Injected write interruption');
    }
    await super.write(file, bytes);
    if (fail && after) {
      throw const FileSystemException('Injected post-write interruption');
    }
  }

  @override
  Future<void> remove(File file) async {
    final fail = ++removes == removeAt;
    if (fail && !after) {
      throw const FileSystemException('Injected delete interruption');
    }
    await super.remove(file);
    if (fail && after) {
      throw const FileSystemException('Injected post-delete interruption');
    }
  }
}
