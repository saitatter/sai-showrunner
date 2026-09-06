import '../../registry/plugin_ui.dart';
import '../../../services/plugin_event_hub.dart';
import 'spellcast_workspace.dart';

DartPluginUiContribution createSpellcastPluginUi(DartPluginEventHub eventHub) =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          SpellcastWorkspace(
            dataService: dataService,
            eventHub: eventHub,
            providerEvents: providerEvents,
          ),
    );
