import 'dart:async';
import 'dart:io';
import '../../persistence/resource_repository.dart';
import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredBluesky(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final blueskySettings = await dataService.loadPluginSettings('bluesky');
  final blueskyIdentifier = blueskySettings['identifier']?.toString().trim();
  final blueskyPassword = blueskySettings['appPassword']?.toString().trim();
  final blueskyServiceUrl = blueskySettings['serviceUrl']?.toString().trim();
  final blueskyHttp = BlueskyHttpTransport(
    baseUrl: blueskyServiceUrl?.isNotEmpty == true
        ? blueskyServiceUrl!
        : 'https://bsky.social',
  );
  final blueskyAccountRepository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/accounts/bluesky'),
    resourceType: 'BlueSkyAccount',
    secretSettings: dataService.secretSettingsStore,
  );
  registry.register(
    createBlueskyPlugin(
      BlueskyTransport(
        blueskyHttp.post,
        postWithSession: blueskyHttp.postWithSession,
      ),
      identifier: blueskyIdentifier,
      appPassword: blueskyPassword,
      accountResolver: (id) async =>
          (await blueskyAccountRepository.load(id))?.config,
    ),
  );
}

void registerDefaultBluesky(DartPluginRegistry registry) {
  registry.register(
    createBlueskyPlugin(BlueskyTransport(_unconfiguredBluesky)),
  );
}

Future<RuntimeMap> _unconfiguredBluesky(
  String identifier,
  String appPassword,
  String text,
) => Future<RuntimeMap>.error(
  StateError('Bluesky transport is not configured.'),
);
