import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredVoiceMod(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final voiceModSettings = await dataService.loadPluginSettings('voicemod');
  final voiceModHost = voiceModSettings['host']?.toString().trim();
  final voiceModTransport = VoiceModWebSocketTransport(
    host: voiceModHost?.isNotEmpty == true ? voiceModHost! : '127.0.0.1',
    port: pluginPort(voiceModSettings['port'], 59129),
  );
  registry.register(
    createVoiceModPlugin(voiceModTransport),
    onStop: voiceModTransport.close,
  );
}

void registerDefaultVoiceMod(DartPluginRegistry registry) {
  final voiceModTransport = CallbackVoiceModTransport(
    getVoicesCallback: _unconfiguredVoiceModVoices,
    selectVoiceCallback: _unconfiguredVoiceMod,
  );
  registry.register(
    createVoiceModPlugin(voiceModTransport),
    onStop: voiceModTransport.close,
  );
}

Future<List<RuntimeMap>> _unconfiguredVoiceModVoices() =>
    Future.error(StateError('VoiceMod transport is not configured.'));

Future<RuntimeMap> _unconfiguredVoiceMod(String voiceId) =>
    Future.error(StateError('VoiceMod transport is not configured.'));
