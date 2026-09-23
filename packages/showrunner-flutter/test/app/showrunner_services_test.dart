import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/bootstrap/showrunner_services.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'composes configured runtime services and shuts them down cleanly',
    () async {
      final root = Directory(
        '${Directory.current.path}/.tmp/showrunner-services-test',
      );
      await root.create(recursive: true);
      addTearDown(() => root.delete(recursive: true));
      const inputChannel = MethodChannel('showrunner/input');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(inputChannel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(inputChannel, null),
      );
      final endpointProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final endpointPort = endpointProbe.port;
      await endpointProbe.close();
      final dataService = ShowRunnerDataService(root);
      await dataService.savePluginSettings('ShowRunner', {
        'port': endpointPort,
      });
      final services = ShowRunnerServices.create(
        dataService: dataService,
        onVariableChanged: (_, _) {},
      );

      await services.start();
      final registry = await services.pluginRegistryFuture;
      expect(registry.findPlugin('obs'), isNotNull);
      expect(registry.findPlugin('twitch'), isNotNull);
      expect(await services.profileManagerFuture, isNotNull);

      await services.shutdown();
      await services.shutdown();
    },
  );
}
