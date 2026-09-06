import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import 'manifest.dart';

typedef WyzeAccountLogin =
    Future<WyzeToken> Function(String email, String password);

/// Owns the account-resource login flow used by the Wyze integration UI.
final class WyzeAccountAuthService {
  WyzeAccountAuthService({required this.dataService, this.login});

  final ShowRunnerDataService dataService;
  final WyzeAccountLogin? login;

  Future<ResourceData> signIn({
    required String email,
    required String password,
    String? name,
  }) async {
    final normalizedEmail = email.trim();
    final normalizedPassword = password.trim();
    if (normalizedEmail.isEmpty || normalizedPassword.isEmpty) {
      throw ArgumentError('Wyze email and password are required.');
    }
    final settings = await dataService.loadPluginSettings('wyze');
    final transport = WyzeHttpTransport(
      keyId: settings['keyId']?.toString() ?? '',
      apiKey: settings['apiKey']?.toString() ?? '',
    );
    final tokens = login == null
        ? await transport.login(normalizedEmail, normalizedPassword)
        : await login!(normalizedEmail, normalizedPassword);
    final existing = await _repository.load('main');
    final account = ResourceData(
      id: 'main',
      config: {
        ...existing?.config ?? <String, dynamic>{},
        'name': name?.trim().isNotEmpty == true
            ? name!.trim()
            : existing?.config['name'] ?? 'Wyze',
        'email': normalizedEmail,
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
      },
      state: {...?existing?.state, 'authenticated': true},
    );
    await _repository.save(account);
    return account;
  }

  Future<ResourceData?> loadAccount() => _repository.load('main');

  Future<void> deleteAccount() => _repository.delete('main');

  ResourceRepository get _repository => ResourceRepository(
    Directory('${dataService.userDirectory.path}/accounts/wyze'),
    resourceType: 'WyzeAccount',
    secretSettings: dataService.secretSettingsStore,
  );
}

Future<JsonMap> loadWyzeAccountSettings(
  ShowRunnerDataService dataService,
) async {
  final settings = await dataService.loadPluginSettings('wyze');
  final repository = _repository(dataService);
  final account = await repository.load('main');
  if (account == null) return settings;
  return {
    ...settings,
    if (_isText(account.config['email'])) 'email': account.config['email'],
    if (_isText(account.config['accessToken']))
      'accessToken': account.config['accessToken'],
    if (_isText(account.config['refreshToken']))
      'refreshToken': account.config['refreshToken'],
  };
}

Future<void> saveWyzeAccountTokens(
  ShowRunnerDataService dataService, {
  required String accessToken,
  required String refreshToken,
}) async {
  final repository = _repository(dataService);
  final account = await repository.load('main');
  if (account == null) {
    final current = await dataService.loadPluginSettings('wyze');
    await dataService.savePluginSettings('wyze', {
      ...current,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    });
    return;
  }
  await repository.save(
    ResourceData(
      id: account.id,
      config: {
        ...account.config,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      },
      state: account.state,
    ),
  );
}

ResourceRepository _repository(ShowRunnerDataService dataService) =>
    ResourceRepository(
      Directory('${dataService.userDirectory.path}/accounts/wyze'),
      resourceType: 'WyzeAccount',
      secretSettings: dataService.secretSettingsStore,
    );

bool _isText(Object? value) => value?.toString().trim().isNotEmpty == true;
