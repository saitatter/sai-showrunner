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
      final services = ShowRunnerServices.create(
        dataService: ShowRunnerDataService(root),
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
