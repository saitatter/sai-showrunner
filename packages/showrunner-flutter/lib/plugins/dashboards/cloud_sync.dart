import 'dart:convert';
import 'dart:io';

import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';

/// Synchronizes the share registration used by the dashboard satellite.
///
/// Dashboard JSON remains the local source of truth. Cloud synchronization is
/// an explicit side effect of saving a dashboard and the returned resource
/// carries the server-generated [cloudId] back into local persistence.
final class DashboardCloudSyncService {
  const DashboardCloudSyncService({required this.dataService});

  final ShowRunnerDataService dataService;

  Future<ResourceData> synchronize(ResourceData resource) async {
    final config = resource.config;
    final allowedTwitchIds = _strings(config['remoteTwitchIds']);
    final cloudId = config['cloudId']?.toString().trim() ?? '';
    if (allowedTwitchIds.isEmpty && cloudId.isEmpty) return resource;

    final twitch = await dataService.loadPluginSettings('twitch');
    final accessToken = twitch['accessToken']?.toString().trim() ?? '';
    if (accessToken.isEmpty) {
      throw StateError(
        'Twitch access token is required to synchronize dashboard sharing.',
      );
    }

    final remote = await dataService.loadPluginSettings('remote');
    final configuredBase = remote['apiBase']?.toString().trim() ?? '';
    final base =
        (configuredBase.isEmpty ? 'https://api.ShowRunner.io' : configuredBase)
            .replaceFirst(RegExp(r'/+$'), '');
    final endpoint = '$base/api/dashboard-access';

    if (allowedTwitchIds.isEmpty) {
      await _request(
        method: 'DELETE',
        uri: Uri.parse('$endpoint/$cloudId'),
        accessToken: accessToken,
      );
      final nextConfig = <String, dynamic>{...config}..remove('cloudId');
      return ResourceData(
        id: resource.id,
        config: nextConfig,
        state: resource.state,
      );
    }

    final body = <String, dynamic>{
      'dashboardId': resource.id,
      'dashboardName': config['name']?.toString() ?? resource.id,
      'allowedTwitchIds': allowedTwitchIds,
    };
    if (cloudId.isNotEmpty) {
      await _request(
        method: 'PUT',
        uri: Uri.parse('$endpoint/$cloudId'),
        accessToken: accessToken,
        body: body,
      );
      return resource;
    }

    final response = await _request(
      method: 'POST',
      uri: Uri.parse('$endpoint/'),
      accessToken: accessToken,
      body: body,
    );
    final createdId = response is Map ? response['_id']?.toString().trim() : '';
    if (createdId == null || createdId.isEmpty) {
      throw const FormatException(
        'Dashboard sharing response did not contain a cloud id.',
      );
    }
    return ResourceData(
      id: resource.id,
      config: {...config, 'cloudId': createdId},
      state: resource.state,
    );
  }

  Future<Object?> _request({
    required String method,
    required Uri uri,
    required String accessToken,
    Object? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $accessToken')
        ..contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Dashboard sharing request failed (${response.statusCode}): $text',
          uri: uri,
        );
      }
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
