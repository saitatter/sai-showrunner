import '../../schema/json.dart';
import '../../services/oauth_token.dart';
import '../../services/showrunner_data_service.dart';

OAuthTokenManager? createPluginTokenManager({
  required String pluginId,
  required JsonMap settings,
  required ShowRunnerDataService dataService,
  required String endpoint,
}) {
  final accessToken = settings['accessToken'] as String?;
  final refreshToken = settings['refreshToken'] as String?;
  final clientId = settings['clientId'] as String?;
  final clientSecret = settings['clientSecret'] as String?;
  final canUsePublicTwitchToken =
      pluginId == 'twitch' && accessToken?.isNotEmpty == true;
  final canUsePublicYouTubeClient = pluginId == 'youtube';
  if ((accessToken?.isNotEmpty != true && refreshToken?.isNotEmpty != true) ||
      clientId?.isNotEmpty != true ||
      (clientSecret?.isNotEmpty != true &&
          !canUsePublicTwitchToken &&
          !canUsePublicYouTubeClient)) {
    return null;
  }
  final rawExpiry = settings['expiresAt'];
  final expiresAt = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
  final effectiveRefreshToken =
      pluginId == 'twitch' && clientSecret?.isNotEmpty != true
      ? null
      : refreshToken;
  final manager = OAuthTokenManager(
    current: OAuthTokenSet(
      accessToken: accessToken ?? '',
      refreshToken: effectiveRefreshToken,
      expiresAt: expiresAt,
    ),
    refresh: (token) async {
      final next = await const OAuthTokenClient().refresh(
        tokenEndpoint: endpoint,
        clientId: clientId!,
        clientSecret: clientSecret,
        refreshToken: token,
      );
      await dataService.savePluginSettings(pluginId, {
        ...settings,
        'accessToken': next.accessToken,
        if (next.refreshToken != null) 'refreshToken': next.refreshToken,
        if (next.expiresAt != null)
          'expiresAt': next.expiresAt!.toIso8601String(),
      });
      return next;
    },
  );
  return manager;
}
