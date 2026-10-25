import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'filesystem/atomic_file.dart';
import 'filesystem/file_transaction.dart';
import 'filesystem/persistence_directory.dart';
import 'filesystem/safe_path.dart';

/// Encrypted file payloads with an OS-keyring key; no plaintext fallback.
/// The public random key ID travels with portable data, while key material stays
/// bound to the current OS account. A missing key never creates a replacement.
final class DesktopSecretCipher {
  DesktopSecretCipher({
    required this.directory,
    this.location,
    Future<String?> Function(String)? readKey,
    Future<void> Function(String, String)? writeKey,
  }) : readKey = readKey ?? _readKey,
       writeKey = writeKey ?? _writeKey;
  final Directory directory;
  final PersistenceDirectory? location;
  final Future<String?> Function(String) readKey;
  final Future<void> Function(String, String) writeKey;
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static Future<String?> _readKey(String id) =>
      _storage.read(key: 'io.showrunner.cipher.v1.$id');
  static Future<void> _writeKey(String id, String key) =>
      _storage.write(key: 'io.showrunner.cipher.v1.$id', value: key);
  static final _algorithm = AesGcm.with256bits();
  Future<File> _metadata() =>
      location?.file(['.platform-key.json']) ??
      containedFile(directory, ['.platform-key.json']);

  Future<(String, SecretKey)> _key({required bool create}) =>
      FileTransaction(
        directory: directory,
        location: location,
        id: 'native-cipher-key',
        targets: const {},
      ).locked(() async {
        final file = await _metadata();
        String id;
        String? encoded;
        if (await file.exists()) {
          final metadata = jsonDecode(await file.readAsString());
          if (metadata is! Map ||
              metadata['version'] != 1 ||
              metadata['id'] is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(metadata['id'] as String)) {
            throw const FormatException('Invalid platform key identity.');
          }
          id = metadata['id'] as String;
          encoded = await readKey(id);
          if (encoded == null) {
            throw StateError('The OS keyring key is unavailable.');
          }
        } else {
          if (!create) {
            throw StateError('The OS keyring identity is unavailable.');
          }
          if (await directory
              .list(recursive: true, followLinks: false)
              .any(
                (entry) =>
                    entry.path.endsWith('.yaml') ||
                    entry.path.endsWith('.json'),
              )) {
            throw StateError(
              'Existing secrets have lost their OS keyring identity.',
            );
          }
          final random = Random.secure();
          id = List.generate(
            32,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
          encoded = base64Encode(
            await (await _algorithm.newSecretKey()).extractBytes(),
          );
          await writeKey(id, encoded);
          if (await readKey(id) != encoded) {
            throw StateError('The OS keyring did not retain the key.');
          }
          await writeAtomicBytes(
            file,
            utf8.encode(jsonEncode({'version': 1, 'id': id})),
          );
        }
        final bytes = base64Decode(encoded);
        if (bytes.length != 32) {
          throw const FormatException('Invalid OS keyring key.');
        }
        return (id, SecretKey(bytes));
      });

  Future<List<int>> encrypt(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw const FormatException('Secret payload limit exceeded.');
    }
    final (id, key) = await _key(create: true);
    final box = await _algorithm.encrypt(bytes, secretKey: key);
    return utf8.encode(
      jsonEncode({
        'version': 1,
        'keyId': id,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }

  Future<List<int>> decrypt(List<int> bytes) async {
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('Secret payload limit exceeded.');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['version'] != 1 ||
        ![
          'keyId',
          'nonce',
          'ciphertext',
          'mac',
        ].every((key) => value[key] is String)) {
      throw const FormatException('Unsupported platform secret payload.');
    }
    final (id, key) = await _key(create: false);
    if (value['keyId'] != id) {
      throw StateError(
        'Secret payload belongs to another OS keyring identity.',
      );
    }
    final nonce = base64Decode(value['nonce'] as String),
        mac = base64Decode(value['mac'] as String);
    if (nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Invalid platform secret payload.');
    }
    return _algorithm.decrypt(
      SecretBox(
        base64Decode(value['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: key,
    );
  }
}
