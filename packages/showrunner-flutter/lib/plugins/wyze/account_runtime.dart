import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';

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
