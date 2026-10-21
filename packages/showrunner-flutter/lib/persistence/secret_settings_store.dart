import 'filesystem/persistence_directory.dart';
import 'secret_storage_exception.dart';
import 'document_codec.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../schema/json.dart';
import 'filesystem/atomic_file.dart';
import 'filesystem/safe_path.dart';
import '../services/structured_logger.dart';

typedef SecretSettingsCipher = Future<List<int>> Function(List<int> bytes);

/// Secret setting names declared by the built-in plugin contracts. The
/// service centralizes these declarations so callers do not have to duplicate
/// the list at every persistence call site.
const Map<String, Set<String>> secretSettingIdsByPlugin = {
  'obs': {'password'},
  'twitch': {'clientSecret', 'accessToken', 'refreshToken'},
  'youtube': {'clientSecret', 'accessToken', 'refreshToken'},
  'chat-dock': {'token'},
  'bluesky': {'appPassword'},
  'govee': {'apiKey'},
  'philips-hue': {'hubKey'},
  'moderation': {'apiToken'},
  'wyze': {'keyId', 'apiKey', 'accessToken', 'refreshToken'},
};

Set<String> secretSettingIdsFor(String pluginId) =>
    secretSettingIdsByPlugin[pluginId.toLowerCase()] ?? const <String>{};

/// Secret fields used by resources whose public configuration is persisted in
/// a normal YAML/JSON resource file. Account resources also use this boundary
/// so sensitive account credentials never get copied to public files.
const Map<String, Set<String>> secretResourceFieldIdsByType = {
  'OBSConnection': {'password'},
  'RCONConnection': {'password'},
  'DiscordWebhook': {'webhookUrl'},
  'Plug': {'hubKey'},
  'TwitchAccount': {'accessToken', 'refreshToken'},
  'BlueSkyAccount': {'appPassword', 'session'},
  'WyzeAccount': {'accessToken', 'refreshToken'},
  'Light': {'hubKey'},
};

Set<String> secretResourceFieldIdsFor(String resourceType) =>
    secretResourceFieldIdsByType[resourceType] ?? const <String>{};

/// Reads and writes the per-plugin secret files used by the desktop app.
///
/// Windows secure storage is backed by DPAPI. Keeping the cipher at this
/// boundary lets tests use an in-memory cipher while the packaged Windows app
/// can read the existing `user/secrets/*.yaml` files.
final class SecretSettingsStore {
  SecretSettingsStore({
    required this.directory,
    this.encrypt,
    this.decrypt,
    this.location,
  });

  final Directory directory;
  final PersistenceDirectory? location;
  final SecretSettingsCipher? encrypt;
  final SecretSettingsCipher? decrypt;

  Future<JsonMap> load(String pluginId) async {
    return _loadFile(_file(pluginId), 'Secret settings');
  }

  Future<void> save(String pluginId, JsonMap values) async {
    await _saveFile(_file(pluginId), values);
  }

  Future<JsonMap> loadResource(String resourceType, String resourceId) async {
    return _loadFile(
      _resourceFile(resourceType, resourceId),
      'Resource secrets',
    );
  }

  Future<void> saveResource(
    String resourceType,
    String resourceId,
    JsonMap values,
  ) async {
    await _saveFile(_resourceFile(resourceType, resourceId), values);
  }

  Future<File> settingsStorageFile(String pluginId) =>
      _contained(_file(pluginId));

  Future<File> resourceStorageFile(String type, String id) =>
      _contained(_resourceFile(type, id));

  Future<File> _contained(File file) async {
    final relative = p.split(
      p.relative(file.absolute.path, from: directory.absolute.path),
    );
    return location?.file(relative) ?? containedFile(directory, relative);
  }

  /// Prepared bytes can participate in a resource/settings redo transaction.
  /// They are ciphertext only; the journal never receives decoded values.
  Future<List<int>> sealValues(JsonMap values, {required String owner}) async {
    ShowRunnerLogger.instance.registerSecrets(values);
    try {
      final plaintext = utf8.encode(encodeYaml(values));
      return List.unmodifiable(
        await (encrypt ?? encryptWithWindowsDpapi)(plaintext),
      );
    } catch (_) {
      throw SecretStorageException(owner: owner, operation: 'write');
    }
  }

  Future<void> deleteResource(String resourceType, String resourceId) async {
    var file = _resourceFile(resourceType, resourceId);
    file = await _contained(file);
    if (await file.exists()) await file.delete();
  }

  Future<JsonMap> _loadFile(File file, String label) async {
    final relative = p.split(
      p.relative(file.absolute.path, from: directory.absolute.path),
    );
    file = await _contained(file);
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final encrypted = await file.readAsBytes();
      final plaintext = await (decrypt ?? decryptWithWindowsDpapi)(encrypted);
      final parsed = loadYaml(utf8.decode(plaintext));
      if (parsed is! YamlMap) {
        throw const FormatException('Secrets must contain a map.');
      }
      final values = decodeYamlValue(parsed) as JsonMap;
      ShowRunnerLogger.instance.registerSecrets(values);
      return values;
    } catch (_) {
      throw SecretStorageException(
        owner: relative.join('/'),
        operation: 'read',
      );
    }
  }

  Future<void> _saveFile(File file, JsonMap values) async {
    final relative = p.split(
      p.relative(file.absolute.path, from: directory.absolute.path),
    );
    file = await _contained(file);
    final encrypted = await sealValues(values, owner: relative.join('/'));
    await writeAtomicBytes(file, encrypted);
  }

  File _file(String pluginId) {
    validateFileIdentifier(pluginId);
    if (!_isSafePluginId(pluginId)) {
      throw ArgumentError.value(pluginId, 'pluginId');
    }
    return File('${directory.path}/$pluginId.yaml');
  }

  File _resourceFile(String resourceType, String resourceId) {
    validateFileIdentifier(resourceType);
    validateFileIdentifier(resourceId);
    if (!_isSafePluginId(resourceType) || !_isSafePluginId(resourceId)) {
      throw ArgumentError(
        'Resource secret path contains an unsafe identifier.',
      );
    }
    return File('${directory.path}/resources/$resourceType/$resourceId.yaml');
  }
}

Future<List<int>> encryptWithWindowsDpapi(List<int> bytes) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Windows DPAPI is only available on Windows.');
  }
  return _protectWindowsDpapi(bytes, unprotect: false);
}

Future<List<int>> decryptWithWindowsDpapi(List<int> bytes) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Windows DPAPI is only available on Windows.');
  }
  return _protectWindowsDpapi(bytes, unprotect: true);
}

typedef _CryptDataNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Utf16> description,
      Pointer<_DataBlob> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptDataDart =
    int Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Utf16> description,
      Pointer<_DataBlob> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      int flags,
      Pointer<_DataBlob> dataOut,
    );

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

List<int> _protectWindowsDpapi(List<int> bytes, {required bool unprotect}) {
  if (bytes.isEmpty) {
    throw const FormatException('Secret settings cannot be empty.');
  }
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final transform = crypt32.lookupFunction<_CryptDataNative, _CryptDataDart>(
    unprotect ? 'CryptUnprotectData' : 'CryptProtectData',
  );
  final localFree = kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');
  final input = calloc<_DataBlob>();
  final inputBytes = calloc<Uint8>(bytes.length);
  final output = calloc<_DataBlob>();
  try {
    inputBytes.asTypedList(bytes.length).setAll(0, bytes);
    input.ref
      ..cbData = bytes.length
      ..pbData = inputBytes;
    final result = transform(
      input,
      Pointer<Utf16>.fromAddress(0),
      Pointer<_DataBlob>.fromAddress(0),
      Pointer<Void>.fromAddress(0),
      Pointer<Void>.fromAddress(0),
      0,
      output,
    );
    if (result == 0 || output.ref.pbData.address == 0) {
      throw StateError(
        'Windows DPAPI could not ${unprotect ? 'decrypt' : 'encrypt'} secret settings.',
      );
    }
    return output.ref.pbData.asTypedList(output.ref.cbData).toList();
  } finally {
    if (output.ref.pbData.address != 0) {
      output.ref.pbData
          .asTypedList(output.ref.cbData)
          .fillRange(0, output.ref.cbData, 0);
      localFree(output.ref.pbData.cast());
    }
    calloc.free(output);
    inputBytes.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
    calloc.free(inputBytes);
    calloc.free(input);
  }
}

bool _isSafePluginId(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
