import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/channel_points.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('maps Twitch reward fields and supports remote CRUD', () async {
    final directory = await Directory.systemTemp.createTemp('twitch-rewards-');
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);
    await dataService.savePluginSettings('twitch', {
      'accessToken': 'token',
      'clientId': 'client',
      'broadcasterId': 'broadcaster-1',
    });

    final requests = <String>[];
    final service = TwitchChannelPointService(
      dataService: dataService,
      request: (method, path, query, body) async {
        requests.add('$method $path ${query['id'] ?? ''}');
        return switch (method) {
          'GET' => {
            'data': [
              {
                'id': 'reward-1',
                'title': 'Hydrate',
                'prompt': 'Take a sip',
                'background_color': '#00aaff',
                'is_enabled': true,
                'cost': 250,
                'is_user_input_required': false,
                'should_redemptions_skip_request_queue': true,
                'is_max_per_stream_enabled': true,
                'max_per_stream': 4,
                'is_global_cooldown_enabled': true,
                'global_cooldown_seconds': 30,
                'redemptions_redeemed_current_stream': 2,
              },
            ],
          },
          'POST' || 'PATCH' => {
            'data': [
              {
                'id': 'reward-1',
                'title': 'Updated',
                'is_enabled': false,
                'cost': 100,
              },
            ],
          },
          _ => <String, dynamic>{},
        };
      },
    );

    final rewards = await service.list();
    final created = await service.create(
      const TwitchChannelPointRewardDraft(
        title: 'Hydrate',
        prompt: 'Take a sip',
        backgroundColor: '#00aaff',
        cost: 250,
        userInputRequired: false,
        skipQueue: true,
        isEnabled: true,
        maxRedemptionsPerStream: 4,
        cooldown: 30,
      ),
    );
    final updated = await service.update(
      'reward-1',
      const TwitchChannelPointRewardDraft(
        title: 'Updated',
        prompt: '',
        backgroundColor: '#9147ff',
        cost: 100,
        userInputRequired: false,
        skipQueue: false,
        isEnabled: false,
      ),
    );
    await service.delete('reward-1');
    await service.updateRedemptionStatus(
      rewardId: 'reward-1',
      redemptionId: 'redemption-1',
      status: 'FULFILLED',
    );

    expect(rewards.single.title, 'Hydrate');
    expect(rewards.single.maxRedemptionsPerStream, 4);
    expect(rewards.single.cooldown, 30);
    expect(rewards.single.redemptionsThisStream, 2);
    expect(created.title, 'Updated');
    expect(updated.isEnabled, isFalse);
    expect(requests, [
      'GET /helix/channel_points/custom_rewards ',
      'POST /helix/channel_points/custom_rewards ',
      'PATCH /helix/channel_points/custom_rewards reward-1',
      'DELETE /helix/channel_points/custom_rewards reward-1',
      'PATCH /helix/channel_points/custom_rewards/redemptions redemption-1',
    ]);
  });

  test('serializes disabled optional limits as explicit Twitch flags', () {
    final draft = TwitchChannelPointRewardDraft.fromConfig({
      'name': 'Reward',
      'rewardData': {
        'cost': 0,
        'maxRedemptionsPerStream': 0,
        'maxRedemptionsPerUserPerStream': 0,
        'cooldown': 0,
      },
      'isEnabled': false,
    });

    expect(draft.cost, 1);
    expect(draft.toRequestBody(), {
      'title': 'Reward',
      'prompt': '',
      'cost': 1,
      'is_enabled': false,
      'background_color': '#9147ff',
      'is_user_input_required': false,
      'is_max_per_stream_enabled': false,
      'is_max_per_user_per_stream_enabled': false,
      'is_global_cooldown_enabled': false,
      'should_redemptions_skip_request_queue': false,
    });
  });

  test('exposes channel point management as graph actions', () async {
    final calls = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        createTwitchPlugin(
          TwitchTransport((method, path, query, body) async {
            calls.add('$method $path ${query['id'] ?? ''}');
            return <String, dynamic>{};
          }),
        ),
      );

    await registry.invokeAction('twitch', 'listChannelPointRewards', {});
    await registry.invokeAction('twitch', 'createChannelPointReward', {
      'name': 'Reward',
      'rewardData': {'cost': 100},
    });
    await registry.invokeAction('twitch', 'updateChannelPointReward', {
      'rewardId': 'reward-1',
      'name': 'Reward',
    });
    await registry.invokeAction('twitch', 'deleteChannelPointReward', {
      'rewardId': 'reward-1',
    });
    await registry.invokeAction('twitch', 'updateChannelPointRedemption', {
      'rewardId': 'reward-1',
      'redemptionId': 'redemption-1',
      'status': 'CANCELED',
    });

    expect(calls, [
      'GET /helix/channel_points/custom_rewards ',
      'POST /helix/channel_points/custom_rewards ',
      'PATCH /helix/channel_points/custom_rewards reward-1',
      'DELETE /helix/channel_points/custom_rewards reward-1',
      'PATCH /helix/channel_points/custom_rewards/redemptions redemption-1',
    ]);
  });
}
