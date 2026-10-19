import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../../services/http_provider_transports.dart';

typedef ModerationRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class ModerationService {
  ModerationService({required this.dataService, ModerationRequest? request})
    : _request = request,
      _usesInjectedRequest = request != null;

  final ShowRunnerDataService dataService;
  ModerationRequest? _request;
  final bool _usesInjectedRequest;
  ModerationSettings? _settings;
  ModerationStatus _status = const ModerationStatus();
  WebSocket? _dashboardSocket;
  Timer? _reconnectTimer;
  bool _disposed = false;
  final _statusChanges = StreamController<ModerationStatus>.broadcast();

  ModerationStatus get status => _status;
  Stream<ModerationStatus> get statusChanges => _statusChanges.stream;

  Future<ModerationSettings> loadSettings() async {
    final values = await dataService.loadPluginSettings('moderation');
    return _settings = ModerationSettings.fromMap(values);
  }

  Future<void> saveSettings(ModerationSettings settings) async {
    _settings = settings;
    if (!_usesInjectedRequest) _request = null;
    await dataService.savePluginSettings('moderation', settings.toMap());
    _status = _status.copyWith(
      enabled: settings.enabled,
      apiBaseUrl: settings.apiBaseUrl,
      dashboardWsUrl: settings.dashboardWsUrl,
      forwardYouTube: settings.forwardYouTube,
    );
  }

  Future<ModerationStatus> checkHealth() async {
    final settings = _settings ?? await loadSettings();
    if (!settings.enabled) {
      _status = _status.copyWith(
        enabled: false,
        health: 'unknown',
        statusMessage: 'Moderation docker forwarding is disabled.',
      );
      return _status;
    }
    try {
      await _send(settings, 'GET', '/healthz', null);
      _status = _status.copyWith(
        enabled: true,
        health: 'healthy',
        statusMessage: 'Moderation docker is reachable.',
      );
    } catch (error) {
      _status = _status.copyWith(
        enabled: true,
        health: 'error',
        statusMessage: '$error',
      );
    }
    return _status;
  }

  Future<RuntimeMap> getQueue() async {
    final settings = _settings ?? await loadSettings();
    return _send(settings, 'GET', '/api/moderation/queue', null);
  }

  Future<RuntimeMap> requestOverride({
    required String messageId,
    required String action,
    String operatorId = 'showrunner',
    String reason = 'ShowRunner moderation override',
  }) async {
    final settings = _settings ?? await loadSettings();
    await _send(settings, 'POST', '/v1/overrides', {
      'messageId': messageId,
      'action': action,
      'operatorId': operatorId,
      'reason': reason,
    });
    _status = _status.copyWith(
      approvedMessages: action == 'approve'
          ? _status.approvedMessages + 1
          : null,
      blockedMessages: action == 'block' ? _status.blockedMessages + 1 : null,
    );
    return getQueue();
  }

  Future<ModerationStatus> sendTestMessage() async {
    final settings = _settings ?? await loadSettings();
    if (!settings.enabled) return _status;
    await _send(settings, 'POST', '/v1/chat-events', {
      'id': 'showrunner-test-${DateTime.now().millisecondsSinceEpoch}',
      'messageId': 'showrunner-test',
      'type': 'chat.message',
      'source': 'showrunner',
      'platform': 'showrunner',
      'message': 'ShowRunner moderation docker test event.',
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
    });
    _status = _status.copyWith(
      processedMessages: _status.processedMessages + 1,
      statusMessage: 'Moderation test event sent.',
    );
    return _status;
  }

  Future<RuntimeMap> moderateChatMessage(RuntimeMap input) async {
    final messageId = input['messageId']?.toString().trim().isNotEmpty == true
        ? input['messageId'].toString()
        : 'showrunner-${DateTime.now().millisecondsSinceEpoch}';
    final platform = (input['platform']?.toString() ?? 'unknown').toLowerCase();
    final viewerName = input['viewerName']?.toString() ?? 'unknown';
    final message = input['message']?.toString() ?? '';
    final badges = input['badges'] is String
        ? (input['badges'] as String)
              .split(',')
              .map((badge) => badge.trim())
              .where((badge) => badge.isNotEmpty)
              .toList()
        : const <String>[];
    final settings = _settings ?? await loadSettings();
    if (!settings.enabled) {
      return _actionResult({
        'messageId': messageId,
        'verdict': 'disabled',
        'confidence': 0,
        'category': 'disabled',
        'reason': 'Moderation docker integration is disabled.',
      });
    }
    try {
      final response = await _send(settings, 'POST', '/v1/chat-events', {
        'id': messageId,
        'messageId': messageId,
        'type': 'chat.message',
        'source': platform,
        'platform': platform,
        'userId': input['viewerId'],
        'username': viewerName,
        'text': message,
        'actor': {
          'id': input['viewerId'] ?? '',
          'name': viewerName,
          'displayName': viewerName,
          'badges': badges,
        },
        'payload': {
          'message': message,
          'isModerator': input['isModerator'] == true,
          'isMember': input['isMember'] == true,
          'isOwner': input['isOwner'] == true,
        },
        'badges': badges,
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
        'deliveryMode': 'decisionOnly',
      });
      _status = _status.copyWith(
        processedMessages: _status.processedMessages + 1,
        lastEventAt: DateTime.now().toUtc().toIso8601String(),
        statusMessage: 'Moderated $platform message through moderation docker.',
      );
      final moderation = response['moderation'] is Map
          ? Map<String, dynamic>.from(response['moderation'] as Map)
          : const <String, dynamic>{};
      return _actionResult({...moderation, 'messageId': messageId});
    } catch (error) {
      _status = _status.copyWith(health: 'error', statusMessage: '$error');
      return _actionResult({
        'messageId': messageId,
        'verdict': 'error',
        'status': 'error',
        'confidence': 0,
        'category': 'error',
        'reason': '$error',
        'backendError': true,
        'errorMessage': '$error',
      });
    }
  }

  Future<void> connectDashboard() async {
    final settings = _settings ?? await loadSettings();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _dashboardSocket?.close();
    _dashboardSocket = null;
    if (!settings.enabled) {
      _status = _status.copyWith(connected: false);
      _publishStatus();
      return;
    }
    try {
      final socket = await WebSocket.connect(
        settings.dashboardWsUrl,
        headers: {
          if (settings.apiToken.isNotEmpty)
            'Authorization': 'Bearer ${settings.apiToken}',
        },
      );
      _dashboardSocket = socket;
      _status = _status.copyWith(
        connected: true,
        statusMessage: 'Connected to moderation dashboard websocket.',
      );
      _publishStatus();
      socket.listen(
        (data) => _handleDashboardMessage(data.toString()),
        onError: (Object error) {
          _status = _status.copyWith(connected: false, statusMessage: '$error');
          _publishStatus();
        },
        onDone: () {
          _dashboardSocket = null;
          _status = _status.copyWith(connected: false);
          _publishStatus();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (error) {
      _status = _status.copyWith(connected: false, statusMessage: '$error');
      _publishStatus();
      _scheduleReconnect();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _dashboardSocket?.close();
    await _statusChanges.close();
  }

  void _handleDashboardMessage(String raw) {
    try {
      final packet = jsonDecode(raw) as Map<String, dynamic>;
      final decision = (packet['verdict'] ?? packet['status'] ?? '')
          .toString()
          .toLowerCase();
      final normalized = decision.isEmpty
          ? (packet['type'] ?? packet['eventType'] ?? 'dashboard.event')
                .toString()
          : decision;
      final receivedAt = DateTime.now().toUtc().toIso8601String();
      _status = _status.copyWith(
        approvedMessages: ['allow', 'approved'].contains(decision)
            ? _status.approvedMessages + 1
            : null,
        blockedMessages: ['block', 'blocked', 'rejected'].contains(decision)
            ? _status.blockedMessages + 1
            : null,
        flaggedMessages: ['flag', 'flagged', 'pending'].contains(decision)
            ? _status.flaggedMessages + 1
            : null,
        lastDecision: normalized,
        lastEventAt: receivedAt,
        recentDecisions: [
          ModerationDecision(
            decision: normalized,
            eventType:
                (packet['type'] ?? packet['eventType'] ?? 'dashboard.event')
                    .toString(),
            messageId: (packet['messageId'] ?? packet['id'])?.toString(),
            receivedAt: receivedAt,
          ),
          ..._status.recentDecisions,
        ].take(10).toList(),
      );
      _publishStatus();
    } on Object {
      // Dashboard can send non-JSON frames during connection setup.
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null || _settings?.enabled != true) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      unawaited(connectDashboard());
    });
  }

  void _publishStatus() {
    if (!_statusChanges.isClosed) _statusChanges.add(_status);
  }

  Future<RuntimeMap> _send(
    ModerationSettings settings,
    String method,
    String path,
    dynamic body,
  ) {
    _request ??= JsonHttpTransport(
      baseUrl: settings.apiBaseUrl,
      headers: {
        if (settings.apiToken.isNotEmpty)
          'Authorization': 'Bearer ${settings.apiToken}',
      },
    ).request;
    return _request!(method, path, const {}, body);
  }

  RuntimeMap _actionResult(RuntimeMap values) {
    final verdict = values['verdict']?.toString() ?? 'unknown';
    final approved =
        values['approved'] == true || ['allow', 'approved'].contains(verdict);
    final blocked =
        values['blocked'] == true ||
        ['block', 'blocked', 'rejected'].contains(verdict);
    final flagged =
        values['flagged'] == true ||
        ['flag', 'flagged', 'pending'].contains(verdict);
    return {
      'verdict': verdict,
      'status': values['status']?.toString() ?? verdict,
      'confidence': values['confidence'] is num ? values['confidence'] : 0,
      'category': values['category']?.toString() ?? 'unknown',
      'reason': values['reason']?.toString() ?? '',
      'messageId': values['messageId']?.toString() ?? '',
      'approved': approved,
      'blocked': blocked,
      'flagged': flagged,
      'backendError': values['backendError'] == true,
      'errorMessage': values['errorMessage']?.toString() ?? '',
    };
  }
}

final class ModerationSettings {
  const ModerationSettings({
    this.enabled = false,
    this.apiBaseUrl = 'http://localhost:8787',
    this.apiToken = '',
    this.dashboardWsUrl = 'ws://localhost:8787/ws?channel=dashboard',
    this.forwardYouTube = true,
  });

  final bool enabled;
  final String apiBaseUrl;
  final String apiToken;
  final String dashboardWsUrl;
  final bool forwardYouTube;

  factory ModerationSettings.fromMap(RuntimeMap values) => ModerationSettings(
    enabled: values['enabled'] == true,
    apiBaseUrl: values['apiBaseUrl']?.toString() ?? 'http://localhost:8787',
    apiToken: values['apiToken']?.toString() ?? '',
    dashboardWsUrl:
        values['dashboardWsUrl']?.toString() ??
        'ws://localhost:8787/ws?channel=dashboard',
    forwardYouTube: values['forwardYouTube'] != false,
  );

  RuntimeMap toMap() => {
    'enabled': enabled,
    'apiBaseUrl': apiBaseUrl,
    'apiToken': apiToken,
    'dashboardWsUrl': dashboardWsUrl,
    'forwardYouTube': forwardYouTube,
  };
}

final class ModerationStatus {
  const ModerationStatus({
    this.enabled = false,
    this.apiBaseUrl = '',
    this.dashboardWsUrl = '',
    this.forwardYouTube = true,
    this.health = 'unknown',
    this.statusMessage = 'Moderation docker is not connected.',
    this.processedMessages = 0,
    this.approvedMessages = 0,
    this.blockedMessages = 0,
    this.flaggedMessages = 0,
    this.connected = false,
    this.lastEventAt,
    this.lastDecision,
    this.recentDecisions = const [],
  });

  final bool enabled;
  final String apiBaseUrl;
  final String dashboardWsUrl;
  final bool forwardYouTube;
  final String health;
  final String statusMessage;
  final int processedMessages;
  final int approvedMessages;
  final int blockedMessages;
  final int flaggedMessages;
  final bool connected;
  final String? lastEventAt;
  final String? lastDecision;
  final List<ModerationDecision> recentDecisions;

  ModerationStatus copyWith({
    bool? enabled,
    String? apiBaseUrl,
    String? dashboardWsUrl,
    bool? forwardYouTube,
    String? health,
    String? statusMessage,
    int? processedMessages,
    int? approvedMessages,
    int? blockedMessages,
    int? flaggedMessages,
    bool? connected,
    String? lastEventAt,
    String? lastDecision,
    List<ModerationDecision>? recentDecisions,
  }) => ModerationStatus(
    enabled: enabled ?? this.enabled,
    apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    dashboardWsUrl: dashboardWsUrl ?? this.dashboardWsUrl,
    forwardYouTube: forwardYouTube ?? this.forwardYouTube,
    health: health ?? this.health,
    statusMessage: statusMessage ?? this.statusMessage,
    processedMessages: processedMessages ?? this.processedMessages,
    approvedMessages: approvedMessages ?? this.approvedMessages,
    blockedMessages: blockedMessages ?? this.blockedMessages,
    flaggedMessages: flaggedMessages ?? this.flaggedMessages,
    connected: connected ?? this.connected,
    lastEventAt: lastEventAt ?? this.lastEventAt,
    lastDecision: lastDecision ?? this.lastDecision,
    recentDecisions: recentDecisions ?? this.recentDecisions,
  );
}

final class ModerationDecision {
  const ModerationDecision({
    required this.decision,
    required this.eventType,
    required this.receivedAt,
    this.messageId,
  });

  final String decision;
  final String eventType;
  final String receivedAt;
  final String? messageId;
}
