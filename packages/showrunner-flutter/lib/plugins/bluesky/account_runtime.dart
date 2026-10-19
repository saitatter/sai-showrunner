import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../runtime/expression.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import 'manifest.dart';

typedef BlueskyAccountLogin =
    Future<RuntimeMap> Function(String identifier, String appPassword);

/// Owns the account-resource login flow used by the Bluesky integration UI.
final class BlueskyAccountAuthService {
  BlueskyAccountAuthService({required this.dataService, this.login});

  final ShowRunnerDataService dataService;
  final BlueskyAccountLogin? login;

  Future<ResourceData> signIn({
    required String accountId,
    required String identifier,
    required String appPassword,
    String? name,
  }) async {
    final normalizedIdentifier = identifier.trim();
    final password = appPassword.trim();
    if (normalizedIdentifier.isEmpty || password.isEmpty) {
      throw ArgumentError('Bluesky identifier and app password are required.');
    }
    final settings = await dataService.loadPluginSettings('bluesky');
    final serviceUrl = settings['serviceUrl']?.toString().trim();
    final transport = BlueskyHttpTransport(
      baseUrl: serviceUrl?.isNotEmpty == true
          ? serviceUrl!
          : 'https://bsky.social',
    );
    final session = login == null
        ? await transport.login(normalizedIdentifier, password)
        : await login!(normalizedIdentifier, password);
    final accessJwt = session['accessJwt']?.toString().trim() ?? '';
    final did = session['did']?.toString().trim() ?? '';
    if (accessJwt.isEmpty || did.isEmpty) {
      throw const FormatException('Bluesky session response is incomplete.');
    }
    final repository = _repository;
    final existing = await repository.load(accountId.trim());
    final updated = ResourceData(
      id: accountId.trim(),
      config: {
        ...existing?.config ?? <String, dynamic>{},
        'name': name?.trim().isNotEmpty == true
            ? name!.trim()
            : existing?.config['name'] ?? normalizedIdentifier,
        'identifier': normalizedIdentifier,
        'session': session,
      },
      state: {...?existing?.state, 'authenticated': true},
    );
    await repository.save(updated);
    return updated;
  }

  Future<ResourceData?> loadAccount(String accountId) =>
      _repository.load(accountId.trim());

  Future<List<ResourceData>> listAccounts() => _repository.list();

  Future<void> deleteAccount(String accountId) =>
      _repository.delete(accountId.trim());

  ResourceRepository get _repository => ResourceRepository(
    Directory('${dataService.userDirectory.path}/accounts/bluesky'),
    resourceType: 'BlueSkyAccount',
    secretSettings: dataService.secretSettingsStore,
  );
}
