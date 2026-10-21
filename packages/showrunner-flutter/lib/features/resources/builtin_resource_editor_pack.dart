import 'resource_editor_contribution.dart';
import '../../plugins/obs/ui/resource_editor_pack.dart';
import '../../plugins/minecraft/ui/resource_editor_pack.dart';
import '../../plugins/sound/ui/resource_editor_pack.dart';
import '../../plugins/twitch/ui/resource_editor_pack.dart';
import '../../plugins/discord/ui/resource_editor_pack.dart';
import '../../plugins/bluesky/ui/resource_editor_pack.dart';
import '../../plugins/dashboards/ui/resource_editor_pack.dart';
import '../../plugins/spellcast/ui/resource_editor_pack.dart';
import '../../plugins/iot/ui/resource_editor_pack.dart';
import '../../plugins/input/ui/resource_editor_pack.dart';
import '../../plugins/wyze/ui/resource_editor_pack.dart';
import '../../plugins/overlays/ui/resource_editor_pack.dart';
import '../../plugins/stream_plans/ui/resource_editor_pack.dart';
import '../../plugins/variables/ui/resource_editor_pack.dart';

DartResourceEditorRegistry createDefaultResourceEditorRegistry() {
  final registry = DartResourceEditorRegistry();
  for (final contribution in <ResourceEditorContribution>[
    ...createObsResourceEditors(),
    ...createMinecraftResourceEditors(),
    ...createSoundResourceEditors(),
    ...createTwitchResourceEditors(),
    ...createDiscordResourceEditors(),
    ...createBlueskyResourceEditors(),
    ...createDashboardsResourceEditors(),
    ...createSpellcastResourceEditors(),
    ...createIotResourceEditors(),
    ...createInputResourceEditors(),
    ...createWyzeResourceEditors(),
    ...createOverlaysResourceEditors(),
    ...createStreamPlansResourceEditors(),
    ...createVariablesResourceEditors(),
  ]) {
    registry.register(contribution);
  }
  return registry;
}
