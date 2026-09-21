import 'dart:convert';
import 'dart:io';

import '../../schema/automation.dart';
import '../../services/oauth_token.dart';
import '../../services/showrunner_data_service.dart';

const youtubeOAuthScopes = <String>[
  'https://www.googleapis.com/auth/youtube.readonly',
  'https://www.googleapis.com/auth/youtube.force-ssl',
];

const youtubeAuthorizationEndpoint =
    'https://accounts.google.com/o/oauth2/v2/auth';
const youtubeTokenEndpoint = 'https://oauth2.googleapis.com/token';

final class YouTubeProfile {
  const YouTubeProfile({required this.channelId, required this.title});

  final String channelId;
  final String title;
}

typedef YouTubeProfileLoader = Future<YouTubeProfile> Function(String token);

/// Owns the browser-based Google OAuth flow used by setup and the YouTube UI.
///
/// The client ID may be supplied by the user or by a release build through
/// its settings bootstrap. The client secret is optional because PKCE is the
/// required protection for installed desktop clients.
final class YouTubeAuthService {
  YouTubeAuthService({
    required this.dataService,
    OAuthAuthorizationFlow? authorizationFlow,
    OAuthTokenClient? tokenClient,
    this.authorizationEndpoint = youtubeAuthorizationEndpoint,
    this.tokenEndpoint = youtubeTokenEndpoint,
    this.openAuthorizationUrl,
    this.loadProfile,
  }) : authorizationFlow = authorizationFlow ?? const OAuthAuthorizationFlow(),
       tokenClient = tokenClient ?? const OAuthTokenClient();

  final ShowRunnerDataService dataService;
  final OAuthAuthorizationFlow authorizationFlow;
  final OAuthTokenClient tokenClient;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final Future<void> Function(Uri url)? openAuthorizationUrl;
  final YouTubeProfileLoader? loadProfile;

  Future<JsonMap> connect() async {
    final settings = await dataService.loadPluginSettings('youtube');
    final clientId = settings['clientId']?.toString().trim() ?? '';
    final clientSecret = settings['clientSecret']?.toString().trim() ?? '';
    if (clientId.isEmpty) {
      throw StateError(
        'A Google OAuth desktop client ID is required before connecting YouTube.',
      );
    }

    final token = await authorizationFlow.authorize(
      requestBuilder: (redirectUri) {
        final verifier = createOAuthCodeVerifier();
        return const OAuthAuthorizationClient().buildRequest(
          authorizationEndpoint: authorizationEndpoint,
          clientId: clientId,
          redirectUri: redirectUri.toString(),
          state: createOAuthState(),
          scopes: youtubeOAuthScopes,
          codeVerifier: verifier,
        );
      },
      openAuthorizationUrl: openAuthorizationUrl ?? openOAuthUrlInBrowser,
      tokenClient: tokenClient,
      tokenEndpoint: tokenEndpoint,
      clientId: clientId,
      clientSecret: clientSecret.isEmpty ? null : clientSecret,
      callbackPath: '/oauth/youtube/callback',
    );
    final profile = await (loadProfile ?? _loadYouTubeProfile)(
      token.accessToken,
    );
    final next = <String, dynamic>{
      ...settings,
      'clientId': clientId,
      'accessToken': token.accessToken,
      if (token.refreshToken != null) 'refreshToken': token.refreshToken,
      if (token.expiresAt != null)
        'expiresAt': token.expiresAt!.toIso8601String(),
      'channelId': profile.channelId,
      'channelName': profile.title,
    };
    await dataService.savePluginSettings('youtube', next);
    return next;
  }

  Future<YouTubeProfile> _loadYouTubeProfile(String accessToken) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.https('www.googleapis.com', '/youtube/v3/channels', {
          'part': 'snippet',
          'mine': 'true',
        }),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'YouTube profile request failed (${response.statusCode}): $body',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['items'] is! List) {
        throw const FormatException(
          'YouTube profile response did not contain a channel.',
        );
      }
      final items = decoded['items'] as List;
      final first = items.isEmpty ? null : items.first;
      final snippet = first is Map ? first['snippet'] : null;
      final channelId = first is Map ? first['id']?.toString() : null;
      final title = snippet is Map ? snippet['title']?.toString() : null;
      if (channelId == null || channelId.isEmpty) {
        throw StateError('No YouTube channel was returned for this account.');
      }
      return YouTubeProfile(
        channelId: channelId,
        title: title == null || title.isEmpty ? channelId : title,
      );
    } finally {
      client.close(force: true);
    }
  }
}
