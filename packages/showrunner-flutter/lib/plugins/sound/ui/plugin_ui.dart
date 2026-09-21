import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createSoundPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => ResourceBackedPluginWorkspace(
        pluginId: 'sound',
        resourceTypes: const {
          'TTSVoice',
          'TTSVoiceProvider',
          'SoundOutput',
          'AudioSplitterOutput',
        },
        dataService: host.dataService,
        registryFuture: host.registryFuture,
        providerEvents: host.providerEvents,
      ),
    );
