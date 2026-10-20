import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'ui/plugin_ui.dart';

void registerConfiguredSpellcast(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  final spellcastHub = eventHub ?? DartPluginEventHub();
  registry.register(createSpellcastPlugin(eventHub: spellcastHub));
  registry.registerUi('spellcast', createSpellcastPluginUi(spellcastHub));
}

void registerDefaultSpellcast(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  final spellcastHub = eventHub ?? DartPluginEventHub();
  registry.register(createSpellcastPlugin(eventHub: spellcastHub));
  registry.registerUi('spellcast', createSpellcastPluginUi(spellcastHub));
}
