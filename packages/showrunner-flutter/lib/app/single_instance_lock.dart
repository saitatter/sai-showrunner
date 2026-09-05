import 'dart:io';

/// Holds an OS-level lock for the lifetime of the desktop application.
///
/// A second process using the same user directory cannot acquire the lock and
/// should exit before it starts plugin workers or binds the HTTP endpoint.
final class SingleInstanceLock {
  SingleInstanceLock._(this._handle, this.path);

  final RandomAccessFile _handle;
  final String path;
  bool _released = false;

  static Future<SingleInstanceLock?> acquire(Directory userDirectory) async {
    final stateDirectory = Directory('${userDirectory.path}/state');
    await stateDirectory.create(recursive: true);
    final lockFile = File('${stateDirectory.path}/instance.lock');
    final handle = await lockFile.open(mode: FileMode.writeOnlyAppend);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      return null;
    }
    return SingleInstanceLock._(handle, lockFile.path);
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
    }
  }
}
