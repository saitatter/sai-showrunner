import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';

typedef DonorDriveRequest =
    Future<dynamic> Function(String path, RuntimeMap query);

final class DonorDriveTransport {
  const DonorDriveTransport(this.request);

  final DonorDriveRequest request;
}

final class DonorDriveHttpTransport {
  const DonorDriveHttpTransport({
    this.baseUrl = 'https://www.extra-life.org/api',
  });

  final String baseUrl;

  Future<dynamic> request(String path, RuntimeMap query) async {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse(base)
        .resolve(path.replaceFirst(RegExp(r'^/'), ''))
        .replace(
          queryParameters: {
            ...query.map((key, value) => MapEntry(key, '$value')),
          },
        );
    final client = HttpClient();
    try {
      final response = await client
          .getUrl(uri)
          .then((request) => request.close());
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'DonorDrive request failed (${response.statusCode}): $text',
        );
      }
      return text.isEmpty ? null : jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }
}

final class DonorDriveRuntime {
  DonorDriveRuntime({
    required this.transport,
    required this.eventHub,
    required this.apiBase,
    required this.participantId,
    this.pollInterval = const Duration(seconds: 15),
  });

  final DonorDriveTransport transport;
  final DartPluginEventHub eventHub;
  final String apiBase;
  final String participantId;
  final Duration pollInterval;
  Timer? _timer;
  DateTime _lastDonationTime = DateTime.now().toUtc();
  int? _lastDonationCount;
  double? _lastTotal;
  bool _polling = false;

  Future<void> start() async {
    stop();
    await poll();
    _timer = Timer.periodic(pollInterval, (_) => unawaited(poll()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> poll() async {
    if (_polling || participantId.trim().isEmpty) return;
    _polling = true;
    try {
      final participant = await transport.request(
        '/participants/${Uri.encodeComponent(participantId)}',
        const {},
      );
      if (participant is! Map) return;
      final currentDonationCount = _number(
        participant['numDonations'],
      )?.round();
      final currentTotal =
          (_number(participant['sumDonations']) ?? 0) +
          (_number(participant['sumPledges']) ?? 0);
      final previousCount = _lastDonationCount;
      final previousTotal = _lastTotal;
      _lastDonationCount = currentDonationCount;
      _lastTotal = currentTotal;
      eventHub.emit('donorDriveState', {
        'eventName': participant['eventName'],
        'goal': participant['fundraisingGoal'],
        'totalRaised':
            (_number(participant['sumDonations']) ?? 0) +
            (_number(participant['sumPledges']) ?? 0),
        'totalDonations': participant['sumDonations'],
        'totalPledges': participant['sumPledges'],
        'donationCount': currentDonationCount,
      });
      if (previousCount == null ||
          currentDonationCount == null ||
          currentDonationCount <= previousCount) {
        return;
      }
      final since = _lastDonationTime;
      _lastDonationTime = DateTime.now().toUtc();
      final donations = await transport.request(
        '/participants/${Uri.encodeComponent(participantId)}/donations',
        {
          'where': 'createdDateUTC > ${since.toIso8601String()}',
          'orderBy': 'createdDateUTC ASC',
        },
      );
      for (final donation in _maps(donations)) {
        final payload = {
          'donor': donation['displayName'] ?? 'Anonymous',
          'isIncentive': donation['incentiveID'] != null,
          'donorAvatar': donation['avatarImageURL'],
          'amount': donation['amount'],
          'message': donation['message'] ?? '',
        };
        eventHub.emit('donation', payload);
        final incentiveId = donation['incentiveID']?.toString().trim();
        if (incentiveId != null && incentiveId.isNotEmpty) {
          eventHub.emit('incentive', {
            ...payload,
            'incentiveId': incentiveId,
            'incentive': donation['incentive'] ?? incentiveId,
          });
        }
      }
      await _emitMilestones(previousTotal, currentTotal);
    } finally {
      _polling = false;
    }
  }

  Future<void> _emitMilestones(
    double? previousTotal,
    double? currentTotal,
  ) async {
    if (previousTotal == null || currentTotal == null) return;
    final milestones = await transport.request(
      '/participants/${Uri.encodeComponent(participantId)}/milestones',
      const {},
    );
    for (final milestone in _maps(milestones)) {
      final goal = _number(milestone['fundraisingGoal']);
      if (goal == null || previousTotal >= goal || currentTotal < goal) {
        continue;
      }
      eventHub.emit('milestone', {
        'milestoneId': milestone['milestoneID'],
        'milestone': milestone['description'],
        'amount': goal,
      });
    }
  }
}

const _donationSchema = DartDataInputSchema(
  label: 'DonorDrive donation',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Minimum amount',
      key: 'minimumAmount',
      kind: DartDataInputKind.number,
    ),
    DartDataInputSchema(
      label: 'Incentives only',
      key: 'incentive',
      kind: DartDataInputKind.boolean,
      defaultValue: false,
    ),
  ],
);

const _incentiveSchema = DartDataInputSchema(
  label: 'DonorDrive incentive',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Incentive ID',
      key: 'incentive',
      kind: DartDataInputKind.text,
    ),
  ],
);

const _milestoneSchema = DartDataInputSchema(
  label: 'DonorDrive milestone',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Milestone ID',
      key: 'milestone',
      kind: DartDataInputKind.text,
    ),
  ],
);

DartPluginManifest createDonorDrivePlugin(
  DonorDriveRuntime? runtime,
) => DartPluginManifest(
  id: 'donordrive',
  name: 'Donor Drive',
  settings: const [
    DartSettingDefinition(
      id: 'apiBase',
      displayName: 'API Base URL',
      defaultValue: 'https://www.extra-life.org/api',
    ),
    DartSettingDefinition(id: 'participantId', displayName: 'Participant ID'),
    DartSettingDefinition(
      id: 'pollIntervalSeconds',
      displayName: 'Poll Interval (seconds)',
      defaultValue: 15,
    ),
  ],
  states: const [
    DartPluginStateDefinition(id: 'eventName', displayName: 'Event Name'),
    DartPluginStateDefinition(id: 'goal', displayName: 'Goal'),
    DartPluginStateDefinition(id: 'totalRaised', displayName: 'Total Raised'),
    DartPluginStateDefinition(
      id: 'totalDonations',
      displayName: 'Total Donations',
    ),
    DartPluginStateDefinition(
      id: 'donationCount',
      displayName: 'Donation Count',
    ),
    DartPluginStateDefinition(id: 'totalPledges', displayName: 'Total Pledges'),
  ],
  triggers: runtime == null
      ? const []
      : [
          DartTriggerDefinition(
            pluginId: 'donordrive',
            triggerId: 'donation',
            displayName: 'DonorDrive Donation',
            configSchema: _donationSchema,
            listen: () => runtime.eventHub.stream('donation'),
            matches: _matchesDonation,
          ),
          DartTriggerDefinition(
            pluginId: 'donordrive',
            triggerId: 'incentive',
            displayName: 'DonorDrive Incentive',
            configSchema: _incentiveSchema,
            listen: () => runtime.eventHub.stream('incentive'),
            matches: (config, payload) =>
                config['incentive']?.toString().trim().isEmpty != false ||
                config['incentive']?.toString() ==
                    payload['incentiveId']?.toString(),
          ),
          DartTriggerDefinition(
            pluginId: 'donordrive',
            triggerId: 'milestone',
            displayName: 'DonorDrive Milestone',
            configSchema: _milestoneSchema,
            listen: () => runtime.eventHub.stream('milestone'),
            matches: (config, payload) =>
                config['milestone']?.toString().trim().isEmpty != false ||
                config['milestone']?.toString() ==
                    payload['milestoneId']?.toString(),
          ),
        ],
  dispose: runtime == null ? null : () async => runtime.stop(),
);

bool _matchesDonation(RuntimeMap config, RuntimeMap payload) {
  if (config['incentive'] == true && payload['isIncentive'] != true) {
    return false;
  }
  final minimum = _number(config['minimumAmount']);
  final amount = _number(payload['amount']);
  return minimum == null || (amount != null && amount >= minimum);
}

List<RuntimeMap> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
