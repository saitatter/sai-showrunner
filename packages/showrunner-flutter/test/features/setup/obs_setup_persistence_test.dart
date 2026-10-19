import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/setup/obs_setup_persistence.dart';

void main() {
  test(
    'creates and updates the OBS connection selected by obsDefault',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-setup-');
      addTearDown(() => root.delete(recursive: true));
      final directory = Directory('${root.path}/obs/connections');
      const persistence = ObsSetupPersistence();

      final id = await persistence.save(
        directory: directory,
        resourceId: null,
        host: '127.0.0.1',
        port: 4455,
        password: 'first',
      );
      expect(id, startsWith('obs-main-'));
      expect(
        (await persistence.loadSelected(
          directory: directory,
          settings: {'obsDefault': id},
        ))?.config,
        {
          'name': 'Main OBS',
          'host': '127.0.0.1',
          'port': 4455,
          'password': 'first',
          'local': true,
        },
      );

      final updatedId = await persistence.save(
        directory: directory,
        resourceId: id,
        host: 'obs.example.test',
        port: 4456,
        password: 'second',
      );
      expect(updatedId, id);
      final resource = await persistence.loadSelected(
        directory: directory,
        settings: {'obsDefault': id},
      );
      expect(resource?.config['host'], 'obs.example.test');
      expect(resource?.config['port'], 4456);
      expect(resource?.config['password'], 'second');
      expect(resource?.config['local'], false);
    },
  );

  test('recognizes the local OBS host variants used by the desktop app', () {
    expect(isLocalHost('localhost'), isTrue);
    expect(isLocalHost('127.0.0.1'), isTrue);
    expect(isLocalHost('::1'), isTrue);
    expect(isLocalHost('obs.example.test'), isFalse);
  });

  test('tests OBS through an injectable probe', () async {
    String? receivedHost;
    int? receivedPort;
    String? receivedPassword;
    final tester = ObsSetupConnectionTester(
      probe: (host, port, password) async {
        receivedHost = host;
        receivedPort = port;
        receivedPassword = password;
      },
    );

    await tester.verify(host: 'obs.local', port: 4455, password: 'secret');

    expect(receivedHost, 'obs.local');
    expect(receivedPort, 4455);
    expect(receivedPassword, 'secret');
  });
}
