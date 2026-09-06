import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createSoundPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          ResourceBackedPluginWorkspace(
            pluginId: 'sound',
            resourceTypes: const {
              'TTSVoice',
              'TTSVoiceProvider',
              'SoundOutput',
              'AudioSplitterOutput',
            },
            dataService: dataService,
            registryFuture: registryFuture,
            providerEvents: providerEvents,
          ),
    );
