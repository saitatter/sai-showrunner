import 'dart:io';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'moderation.dart';
import 'runtime.dart';
import 'ui/plugin_ui.dart';

void registerConfiguredModeration(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) {
  final moderationService = ModerationService(dataService: dataService);
  registry.register(
    createModerationPlugin(moderationService),
    onHealthCheck: () async =>
        (await moderationService.checkHealth()).health == 'healthy',
    onStop: moderationService.dispose,
  );
  registry.registerUi(
    'moderation',
    createModerationPluginUi(moderationService),
  );
}

void registerDefaultModeration(DartPluginRegistry registry) {
  final moderationService = ModerationService(
    dataService: ShowRunnerDataService(Directory.systemTemp),
  );
  registry.register(
    createModerationPlugin(moderationService),
    onHealthCheck: () async =>
        (await moderationService.checkHealth()).health == 'healthy',
    onStop: moderationService.dispose,
  );
  registry.registerUi(
    'moderation',
    createModerationPluginUi(moderationService),
  );
}
