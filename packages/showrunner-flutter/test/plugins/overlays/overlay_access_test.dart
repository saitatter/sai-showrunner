import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_access.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';

void main() {
  test(
    'capabilities bind the installation and resource without exposing the master key',
    () {
      final access = OverlayAccessTokens.fromKey(List.filled(32, 7));
      final token = access.forOverlay('one');
      expect(token, hasLength(43));
      expect(access.accepts('one', token), isTrue);
      expect(access.accepts('two', token), isFalse);
      expect(access.accepts('one', null), isFalse);
      expect(access.accepts('one', '$token-extra'), isFalse);
      expect(
        OverlayAccessTokens.fromKey(List.filled(32, 8)).accepts('one', token),
        isFalse,
      );
    },
  );

  test(
    'concurrent owners persist one secret and preserve malformed stored secrets',
    () async {
      final root = await Directory.systemTemp.createTemp('overlay-access-');
      addTearDown(() => root.delete(recursive: true));
      final data = ShowRunnerDataService(
        root,
        secretSettings: SecretSettingsStore(
          directory: Directory('${root.path}/secrets'),
          encrypt: (bytes) async => bytes.map((byte) => byte ^ 37).toList(),
          decrypt: (bytes) async => bytes.map((byte) => byte ^ 37).toList(),
        ),
      );
      await data.updatePluginSettings('overlays', {'keep': 'public-value'});
      final owners = await Future.wait([
        OverlayAccessTokens.load(data),
        OverlayAccessTokens.load(data),
      ]);
      final token = owners.first.forOverlay('fixture');
      expect(owners.last.forOverlay('fixture'), token);
      expect(
        (await OverlayAccessTokens.load(data)).forOverlay('fixture'),
        token,
      );
      final settings = await data.loadPluginSettings('overlays');
      expect(settings['keep'], 'public-value');
      final publicText = await File(
        '${root.path}/settings/overlays.yaml',
      ).readAsString();
      expect(publicText, isNot(contains('browserSecret')));
      expect(publicText, isNot(contains(settings['browserSecret'])));
      expect(publicText, isNot(contains(token)));
      await data.updatePluginSettings('overlays', {
        'browserSecret': 'malformed',
      });
      await expectLater(OverlayAccessTokens.load(data), throwsFormatException);
      expect(
        (await data.loadPluginSettings('overlays'))['browserSecret'],
        'malformed',
      );
    },
  );
}
