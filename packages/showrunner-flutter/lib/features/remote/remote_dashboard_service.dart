import 'dart:convert';
import 'dart:io';
import '../../services/showrunner_data_service.dart';
import '../../plugins/twitch/account_runtime.dart';

typedef RemoteDashboardFetcher =
    Future<List<RemoteDashboardInfo>> Function(String accessToken);

final class RemoteDashboardInfo {
  const RemoteDashboardInfo({
    required this.ownerId,
    required this.dashboardId,
    required this.name,
  });

  final String ownerId;
  final String dashboardId;
  final String name;

  factory RemoteDashboardInfo.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Remote dashboard must be an object.');
    }
    final json = Map<String, dynamic>.from(value);
    final ownerId = json['ownerId']?.toString().trim() ?? '';
    final dashboardId = json['dashboardId']?.toString().trim() ?? '';
    final name = json['dashboardName']?.toString().trim() ?? '';
    if (ownerId.isEmpty || dashboardId.isEmpty || name.isEmpty) {
      throw const FormatException('Remote dashboard has incomplete identity.');
    }
    return RemoteDashboardInfo(
      ownerId: ownerId,
      dashboardId: dashboardId,
      name: name,
    );
  }
}

final class RemoteDashboardService {
  RemoteDashboardService({required this.dataService, this.fetcher});

  final ShowRunnerDataService dataService;
  final RemoteDashboardFetcher? fetcher;

  Future<List<RemoteDashboardInfo>> listAvailable() async {
    final settings = await loadTwitchChannelSettings(dataService);
    final token = settings['accessToken']?.toString().trim() ?? '';
    if (token.isEmpty) {
      throw StateError(
        'Twitch access token is required to discover remote dashboards.',
      );
    }
    return (fetcher ?? _fetchFromCloud)(token);
  }

  Future<List<RemoteDashboardInfo>> _fetchFromCloud(String token) async {
    final remoteSettings = await dataService.loadPluginSettings('remote');
    final configured = remoteSettings['apiBase']?.toString().trim() ?? '';
    final base = configured.isEmpty ? 'https://api.ShowRunner.io' : configured;
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('$base/api/dashboard-access/remote'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Remote dashboard discovery failed (${response.statusCode}): $text',
        );
      }
      final decoded = text.isEmpty ? const <dynamic>[] : jsonDecode(text);
      if (decoded is! List) {
        throw const FormatException(
          'Remote dashboard discovery must return a list.',
        );
      }
      final dashboards = <RemoteDashboardInfo>[];
      for (final item in decoded) {
        try {
          dashboards.add(RemoteDashboardInfo.fromJson(item));
        } on FormatException {
          // One malformed dashboard must not hide all valid dashboard entries.
        }
      }
      return dashboards;
    } finally {
      client.close(force: true);
    }
  }
}
