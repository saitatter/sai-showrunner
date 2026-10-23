import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../../services/showrunner_data_service.dart';

/// Installation-owned secret; browser capabilities are derived per resource.
final class OverlayAccessTokens {
  OverlayAccessTokens.fromKey(List<int> key) : _key = List.unmodifiable(key) {
    if (key.length != 32 || key.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Invalid overlay access secret.');
    }
  }
  factory OverlayAccessTokens.random() => OverlayAccessTokens.fromKey(
    List.generate(32, (_) => Random.secure().nextInt(256)),
  );
  final List<int> _key;
  static const cookieName = 'showrunner-overlay';

  String forOverlay(String id) => base64UrlEncode(
    Hmac(
      sha256,
      _key,
    ).convert(utf8.encode('overlay-browser-v1\u0000$id')).bytes,
  ).replaceAll('=', '');

  bool accepts(String id, String? token) {
    final expected = forOverlay(id);
    if (token == null || token.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected.codeUnitAt(index) ^ token.codeUnitAt(index);
    }
    return difference == 0;
  }

  static Future<OverlayAccessTokens> load(ShowRunnerDataService data) async {
    OverlayAccessTokens decode(Object? value) {
      if (value is! String) {
        throw const FormatException('Invalid overlay access secret.');
      }
      return OverlayAccessTokens.fromKey(base64Url.decode(value));
    }

    final current = await data.loadPluginSettings('overlays');
    if (current.containsKey('browserSecret')) {
      return decode(current['browserSecret']);
    }
    late OverlayAccessTokens result;
    await data.transformPluginSettings('overlays', (settings) {
      if (settings.containsKey('browserSecret')) {
        result = decode(settings['browserSecret']);
        return settings;
      }
      result = OverlayAccessTokens.random();
      return {...settings, 'browserSecret': base64UrlEncode(result._key)};
    });
    return result;
  }
}
