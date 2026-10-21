import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/viewer_group_editor.dart';
import 'package:showrunner_flutter/features/resources/connection/map_resource_contribution.dart';
import 'editor/channel_point_reward_editor.dart';

List<ResourceEditorContribution> createTwitchResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('CustomTwitchViewerGroup'),
    builder: (context, resource, onSave) =>
        ViewerGroupEditor(resource: resource, onSave: onSave),
  ),
  mapResourceContribution(
    builtInResourceSpec('TwitchAccount'),
    fields: const [
      'name',
      'twitchId',
      'isAffiliate',
      'isPartner',
      'email',
      'accessToken',
      'refreshToken',
    ],
  ),
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('ChannelPointReward'),
    builder: (context, resource, onSave) =>
        ChannelPointRewardEditor(resource: resource, onSave: onSave),
  ),
];
