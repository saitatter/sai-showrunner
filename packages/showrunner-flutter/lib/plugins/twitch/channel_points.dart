import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/showrunner_data_service.dart';
import 'account_runtime.dart';

typedef TwitchChannelPointRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class TwitchChannelPointReward {
  const TwitchChannelPointReward({
    required this.id,
    required this.title,
    required this.prompt,
    required this.backgroundColor,
    required this.isEnabled,
    required this.cost,
    required this.userInputRequired,
    required this.skipQueue,
    this.maxRedemptionsPerStream,
    this.maxRedemptionsPerUserPerStream,
    this.cooldown,
    this.redemptionsThisStream,
  });

  final String id;
  final String title;
  final String prompt;
  final String backgroundColor;
  final bool isEnabled;
  final int cost;
  final bool userInputRequired;
  final bool skipQueue;
  final int? maxRedemptionsPerStream;
  final int? maxRedemptionsPerUserPerStream;
  final int? cooldown;
  final int? redemptionsThisStream;

  factory TwitchChannelPointReward.fromJson(RuntimeMap json) =>
      TwitchChannelPointReward(
        id: _text(json['id']),
        title: _text(json['title']),
        prompt: _text(json['prompt']),
        backgroundColor: _text(json['background_color']),
        isEnabled: json['is_enabled'] == true,
        cost: _int(json['cost']) ?? 1,
        userInputRequired: json['is_user_input_required'] == true,
        skipQueue: json['should_redemptions_skip_request_queue'] == true,
        maxRedemptionsPerStream: json['is_max_per_stream_enabled'] == true
            ? _int(json['max_per_stream'])
            : null,
        maxRedemptionsPerUserPerStream:
            json['is_max_per_user_per_stream_enabled'] == true
            ? _int(json['max_per_user_per_stream'])
            : null,
        cooldown: json['is_global_cooldown_enabled'] == true
            ? _int(json['global_cooldown_seconds'])
            : null,
        redemptionsThisStream: _int(
          json['redemptions_redeemed_current_stream'],
        ),
      );
}

final class TwitchChannelPointRewardDraft {
  const TwitchChannelPointRewardDraft({
    required this.title,
    required this.prompt,
    required this.backgroundColor,
    required this.cost,
    required this.userInputRequired,
    required this.skipQueue,
    required this.isEnabled,
    this.maxRedemptionsPerStream,
    this.maxRedemptionsPerUserPerStream,
    this.cooldown,
  });

  final String title;
  final String prompt;
  final String backgroundColor;
  final int cost;
  final bool userInputRequired;
  final bool skipQueue;
  final bool isEnabled;
  final int? maxRedemptionsPerStream;
  final int? maxRedemptionsPerUserPerStream;
  final int? cooldown;

  factory TwitchChannelPointRewardDraft.fromConfig(RuntimeMap config) {
    final rawData = config['rewardData'];
    final rewardData = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    dynamic value(String key) => rewardData[key] ?? config[key];

    return TwitchChannelPointRewardDraft(
      title: _text(config['title'] ?? config['name']),
      prompt: _text(value('prompt')),
      backgroundColor: _text(value('backgroundColor')).isEmpty
          ? '#9147ff'
          : _text(value('backgroundColor')),
      cost: (_int(value('cost')) ?? 1).clamp(1, 1000000),
      userInputRequired: _bool(value('userInputRequired')),
      skipQueue: _bool(value('skipQueue')),
      isEnabled: value('isEnabled') == null || _bool(value('isEnabled')),
      maxRedemptionsPerStream: _positiveInt(value('maxRedemptionsPerStream')),
      maxRedemptionsPerUserPerStream: _positiveInt(
        value('maxRedemptionsPerUserPerStream'),
      ),
      cooldown: _positiveInt(value('cooldown')),
    );
  }

  RuntimeMap toRequestBody() => {
    'title': title.trim(),
    'prompt': prompt,
    'cost': cost.clamp(1, 1000000),
    'is_enabled': isEnabled,
    'background_color': backgroundColor.trim().isEmpty
        ? '#9147ff'
        : backgroundColor.trim(),
    'is_user_input_required': userInputRequired,
    'is_max_per_stream_enabled': maxRedemptionsPerStream != null,
    if (maxRedemptionsPerStream != null)
      'max_per_stream': maxRedemptionsPerStream,
    'is_max_per_user_per_stream_enabled':
        maxRedemptionsPerUserPerStream != null,
    if (maxRedemptionsPerUserPerStream != null)
      'max_per_user_per_stream': maxRedemptionsPerUserPerStream,
    'is_global_cooldown_enabled': cooldown != null,
    if (cooldown != null) 'global_cooldown_seconds': cooldown,
    'should_redemptions_skip_request_queue': skipQueue,
  };
}

final class TwitchChannelPointService {
  TwitchChannelPointService({required this.dataService, this.request});

  final ShowRunnerDataService dataService;
  final TwitchChannelPointRequest? request;

  Future<List<TwitchChannelPointReward>> list({
    bool onlyManageable = false,
  }) async {
    final response =
        await _request('GET', '/helix/channel_points/custom_rewards', {
          'broadcaster_id': await _broadcasterId(),
          if (onlyManageable) 'only_manageable_rewards': 'true',
        }, null);
    return _data(response)
        .map(TwitchChannelPointReward.fromJson)
        .where((reward) => reward.id.isNotEmpty)
        .toList();
  }

  Future<TwitchChannelPointReward> create(
    TwitchChannelPointRewardDraft draft,
  ) async {
    final response = await _request(
      'POST',
      '/helix/channel_points/custom_rewards',
      {'broadcaster_id': await _broadcasterId()},
      draft.toRequestBody(),
    );
    return _firstReward(response);
  }

  Future<TwitchChannelPointReward> update(
    String rewardId,
    TwitchChannelPointRewardDraft draft,
  ) async {
    final response = await _request(
      'PATCH',
      '/helix/channel_points/custom_rewards',
      {'broadcaster_id': await _broadcasterId(), 'id': rewardId},
      draft.toRequestBody(),
    );
    return _firstReward(response);
  }

  Future<void> delete(String rewardId) async {
    await _request('DELETE', '/helix/channel_points/custom_rewards', {
      'broadcaster_id': await _broadcasterId(),
      'id': rewardId,
    }, null);
  }

  Future<RuntimeMap> updateRedemptionStatus({
    required String rewardId,
    required String redemptionId,
    required String status,
  }) async => _request(
    'PATCH',
    '/helix/channel_points/custom_rewards/redemptions',
    {
      'broadcaster_id': await _broadcasterId(),
      'reward_id': rewardId,
      'id': redemptionId,
    },
    {'status': status},
  );

  Future<RuntimeMap> _request(
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
  ) async {
    final settings = await loadTwitchChannelSettings(dataService);
    final token = settings['accessToken']?.toString().trim() ?? '';
    final clientId = settings['clientId']?.toString().trim() ?? '';
    if (token.isEmpty || clientId.isEmpty) {
      throw StateError('Twitch access token and client ID are required.');
    }
    final fetch =
        request ??
        JsonHttpTransport(
          baseUrl: 'https://api.twitch.tv',
          accessToken: token,
          headers: {'Client-Id': clientId},
        ).request;
    return fetch(method, path, query, body);
  }

  Future<String> _broadcasterId() async {
    final id = (await loadTwitchChannelSettings(
      dataService,
    ))['broadcasterId']?.toString().trim();
    if (id == null || id.isEmpty) {
      throw StateError('Twitch broadcaster ID is required.');
    }
    return id;
  }
}

List<RuntimeMap> _data(RuntimeMap response) {
  final value = response['data'];
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

TwitchChannelPointReward _firstReward(RuntimeMap response) {
  final reward = _data(response).firstOrNull;
  if (reward == null) {
    throw const FormatException('Twitch returned no channel point reward.');
  }
  return TwitchChannelPointReward.fromJson(reward);
}

String _text(Object? value) => value?.toString() ?? '';

bool _bool(Object? value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

int? _positiveInt(Object? value) {
  final valueAsInt = _int(value);
  return valueAsInt == null || valueAsInt < 1 ? null : valueAsInt;
}
