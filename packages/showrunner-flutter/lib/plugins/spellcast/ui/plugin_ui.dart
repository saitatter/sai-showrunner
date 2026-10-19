import '../../registry/plugin_ui.dart';
import '../../../services/plugin_event_hub.dart';
import 'spellcast_workspace.dart';

DartPluginUiContribution createSpellcastPluginUi(DartPluginEventHub eventHub) =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => SpellcastWorkspace(
        dataService: host.dataService,
        eventHub: eventHub,
        providerEvents: host.providerEvents,
      ),
    );
