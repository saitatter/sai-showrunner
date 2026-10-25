import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/desktop_secret_cipher.dart';

void main() {
  test(
    'concurrent owners retain one key and authenticate every ciphertext',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'desktop-secrets-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final keys = <String, String>{};
      var writes = 0;
      DesktopSecretCipher cipher() => DesktopSecretCipher(
        directory: directory,
        readKey: (id) async => keys[id],
        writeKey: (id, key) async {
          writes++;
          keys[id] = key;
        },
      );
      final values = await Future.wait(
        List.generate(12, (i) => cipher().encrypt(utf8.encode('secret-$i'))),
      );
      expect(writes, 1);
      for (var i = 0; i < values.length; i++) {
        expect(utf8.decode(await cipher().decrypt(values[i])), 'secret-$i');
        expect(utf8.decode(values[i]), isNot(contains('secret-$i')));
      }
      final tampered =
          jsonDecode(utf8.decode(values.first)) as Map<String, dynamic>;
      tampered['ciphertext'] = base64Encode(utf8.encode('changed!'));
      await expectLater(
        cipher().decrypt(utf8.encode(jsonEncode(tampered))),
        throwsA(anything),
      );
      final moved = Directory('${directory.path}-moved');
      await directory.rename(moved.path);
      addTearDown(() => moved.delete(recursive: true));
      expect(
        utf8.decode(
          await DesktopSecretCipher(
            directory: moved,
            readKey: (id) async => keys[id],
            writeKey: (_, _) async => fail('must not generate'),
          ).decrypt(values.first),
        ),
        'secret-0',
      );
      await directory.create();
    },
  );
  test(
    'missing key metadata never creates a replacement over stored secrets',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'desktop-missing-identity-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final saved = File('${directory.path}/obs.yaml');
      await saved.writeAsString('existing ciphertext');
      final cipher = DesktopSecretCipher(
        directory: directory,
        readKey: (_) async => null,
        writeKey: (_, _) async => fail('must not replace a missing identity'),
      );
      await expectLater(cipher.encrypt([1]), throwsStateError);
      expect(await saved.readAsString(), 'existing ciphertext');
      expect(
        await File('${directory.path}/.platform-key.json').exists(),
        isFalse,
      );
    },
  );
  test(
    'lost key and unsupported metadata fail without replacing stored identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'desktop-lost-key-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final keys = <String, String>{};
      final cipher = DesktopSecretCipher(
        directory: directory,
        readKey: (id) async => keys[id],
        writeKey: (id, key) async {
          keys[id] = key;
        },
      );
      final bytes = await cipher.encrypt([1, 2, 3]);
      final metadata = File('${directory.path}/.platform-key.json');
      final before = await metadata.readAsString();
      keys.clear();
      await expectLater(cipher.decrypt(bytes), throwsStateError);
      await expectLater(cipher.encrypt([4]), throwsStateError);
      expect(await metadata.readAsString(), before);
      expect(keys, isEmpty);
      await metadata.writeAsString('{"version":999,"id":"future"}');
      await expectLater(cipher.encrypt([4]), throwsFormatException);
      expect(await metadata.readAsString(), contains('999'));
    },
  );
}
