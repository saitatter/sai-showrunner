import 'dart:async';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredDonorDrive(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartPluginEventHub? eventHub,
}) async {
  final donorDriveSettings = await dataService.loadPluginSettings('donordrive');
  final donorDriveApiBase = donorDriveSettings['apiBase']?.toString().trim();
  final donorDriveParticipant = donorDriveSettings['participantId']
      ?.toString()
      .trim();
  final donorDriveInterval = positivePluginDuration(
    donorDriveSettings['pollIntervalSeconds'],
    const Duration(seconds: 15),
  );
  final donorDriveRuntime =
      eventHub != null && donorDriveParticipant?.isNotEmpty == true
      ? DonorDriveRuntime(
          transport: DonorDriveTransport(
            DonorDriveHttpTransport(
              baseUrl: donorDriveApiBase?.isNotEmpty == true
                  ? donorDriveApiBase!
                  : 'https://www.extra-life.org/api',
            ).request,
          ),
          eventHub: eventHub,
          apiBase: donorDriveApiBase ?? 'https://www.extra-life.org/api',
          participantId: donorDriveParticipant!,
          pollInterval: donorDriveInterval,
        )
      : null;
  registry.register(
    createDonorDrivePlugin(donorDriveRuntime),
    onStart: donorDriveRuntime?.start,
    onStop: donorDriveRuntime == null
        ? null
        : () async => donorDriveRuntime.stop(),

    initialHealth: (donorDriveRuntime != null)
        ? const DartPluginHealth.connectionUnchecked()
        : const DartPluginHealth.notConfigured(),
  );
}

void registerDefaultDonorDrive(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  registry.register(
    createDonorDrivePlugin(null, eventHub: eventHub),
    initialHealth: const DartPluginHealth.notConfigured(),
  );
}
