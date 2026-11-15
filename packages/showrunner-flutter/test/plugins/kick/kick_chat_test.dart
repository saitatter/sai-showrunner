import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:showrunner_flutter/plugins/kick/contracts.dart';
import 'package:showrunner_flutter/plugins/kick/webhook_receiver.dart';
import 'package:showrunner_flutter/plugins/kick/webhook_signature.dart';

void main() {
  late _SigningKey key;
  final now = DateTime.utc(2026, 11, 15, 12);

  setUpAll(() => key = _SigningKey(13));

  test('validates visible characters, byte limits and typed IDs', () {
    expect(
      validateKickMessage(List.filled(500, 'a\u0301').join()),
      List.filled(500, 'a\u0301').join(),
    );
    expect(
      () => validateKickMessage(List.filled(501, 'a').join()),
      throwsArgumentError,
    );
    // Only 100 graphemes, but more than 2048 bytes.
    expect(
      () => validateKickMessage(List.filled(100, '👨‍👩‍👧‍👦').join()),
      throwsArgumentError,
    );
    expect(() => validateKickMessage(' \n '), throwsArgumentError);
    expect(kickUserId('9223372036854775807', 'id'), 9223372036854775807);
    for (final invalid in [
      true,
      1.0,
      '01',
      '-1',
      '1.0',
      '9223372036854775808',
    ]) {
      expect(() => kickUserId(invalid, 'id'), throwsArgumentError);
    }
    for (final invalid in ['..', '../secret', 'id?x=y', '', 'a/b']) {
      expect(() => kickMessageId(invalid), throwsArgumentError);
    }
  });

  test('maps user/bot sending and minutes without broadening moderation', () {
    expect(
      KickSendChatConfig.fromRuntime({
        'message': 'hello',
      }).toRequest(defaultBroadcasterId: '7'),
      {'content': 'hello', 'type': 'user', 'broadcaster_user_id': 7},
    );
    expect(
      KickSendChatConfig.fromRuntime({
        'message': 'hello',
        'account': 'bot',
        'broadcasterId': '9',
      }).toRequest(),
      {'content': 'hello', 'type': 'bot'},
    );
    expect(
      () => KickSendChatConfig.fromRuntime({'message': 'hello'}).toRequest(),
      throwsArgumentError,
    );
    final timeout = KickModerationConfig.fromRuntime({
      'userId': '8',
      'durationMinutes': 1,
      'reason': 'test',
    }, timeout: true);
    expect(timeout.toRequest(defaultBroadcasterId: 7), {
      'user_id': 8,
      'broadcaster_user_id': 7,
      'duration': 1,
      'reason': 'test',
    });
    expect(timeout.toRequest(defaultBroadcasterId: 7, unban: true), {
      'user_id': 8,
      'broadcaster_user_id': 7,
    });
    expect(
      () => KickModerationConfig.fromRuntime({
        'userId': 8,
        'durationMinutes': 0,
      }, timeout: true),
      throwsArgumentError,
    );
    expect(
      () =>
          KickModerationConfig.fromRuntime({'userId': 8, 'durationMinutes': 1}),
      throwsArgumentError,
    );
  });

  test(
    'verifies real RSA signatures and rejects changed exact bytes',
    () async {
      var loads = 0;
      final verifier = KickWebhookSignatureVerifier(
        loadPublicKey: () async {
          loads++;
          return key.pem;
        },
        now: () => now,
      );
      addTearDown(verifier.close);
      final timestamp = now.toIso8601String();
      final body = Uint8List.fromList(utf8.encode('{"content":"ș 🎮"}'));
      final signature = key.sign('delivery', timestamp, body);
      expect(
        await verifier.verify(
          messageId: 'delivery',
          timestamp: timestamp,
          signature: signature,
          body: body,
        ),
        isTrue,
      );
      expect(
        await verifier.verify(
          messageId: 'delivery',
          timestamp: timestamp,
          signature: signature,
          body: Uint8List.fromList([...body, 32]),
        ),
        isFalse,
      );
      expect(
        await verifier.verify(
          messageId: 'other',
          timestamp: timestamp,
          signature: signature,
          body: body,
        ),
        isFalse,
      );
      expect(
        await verifier.verify(
          messageId: 'delivery',
          timestamp: now.subtract(const Duration(minutes: 6)).toIso8601String(),
          signature: signature,
          body: body,
        ),
        isFalse,
      );
      expect(
        await verifier.verify(
          messageId: 'delivery',
          timestamp: timestamp,
          signature: 'not base64',
          body: body,
        ),
        isFalse,
      );
      expect(
        loads,
        1,
        reason: 'Invalid signatures must not cause key fetch storms.',
      );
    },
  );

  test('refreshes a rotated key once, then rejects work after close', () async {
    final rotated = _SigningKey(17);
    var clock = now;
    var loads = 0;
    final verifier = KickWebhookSignatureVerifier(
      loadPublicKey: () async {
        loads++;
        return loads == 1 ? key.pem : rotated.pem;
      },
      now: () => clock,
    );
    final body = Uint8List.fromList([1, 2, 3]);
    expect(
      await verifier.verify(
        messageId: 'one',
        timestamp: clock.toIso8601String(),
        signature: key.sign('one', clock.toIso8601String(), body),
        body: body,
      ),
      isTrue,
    );
    clock = clock.add(const Duration(seconds: 31));
    expect(
      await verifier.verify(
        messageId: 'two',
        timestamp: clock.toIso8601String(),
        signature: rotated.sign('two', clock.toIso8601String(), body),
        body: body,
      ),
      isTrue,
    );
    expect(loads, 2);
    verifier.close();
    expect(
      await verifier.verify(
        messageId: 'two',
        timestamp: clock.toIso8601String(),
        signature: rotated.sign('two', clock.toIso8601String(), body),
        body: body,
      ),
      isFalse,
    );
  });

  test(
    'key fetch is single-flight and disposal rejects late completion',
    () async {
      final pending = Completer<String>();
      var loads = 0;
      final verifier = KickWebhookSignatureVerifier(
        loadPublicKey: () {
          loads++;
          return pending.future;
        },
        now: () => now,
      );
      final body = Uint8List.fromList([1]);
      Future<bool> verify(String id) => verifier.verify(
        messageId: id,
        timestamp: now.toIso8601String(),
        signature: key.sign(id, now.toIso8601String(), body),
        body: body,
      );
      final first = verify('one');
      final second = verify('two');
      expect(loads, 1);
      verifier.close();
      pending.complete(key.pem);
      expect(await Future.wait([first, second]), [false, false]);
    },
  );

  test(
    'projects provider identities without trusting badge labels or raw fields',
    () {
      final body = _chat();
      final sender = body['sender'] as Map<String, dynamic>;
      sender['email'] = 'private@example.test';
      sender['is_verified'] = true;
      sender['profile_picture'] = 'https://evil.test/avatar.png';
      sender['identity'] = {
        'badges': [
          {'type': 'other', 'text': 'Moderator'},
          {'type': 'subscriber', 'count': 4},
        ],
      };
      final event = KickWebhookEvent.decode('chat.message.sent', body);
      expect(event.type, 'kickChatMessage');
      expect(event.payload['isModerator'], isFalse);
      expect(event.payload['isSubscriber'], isTrue);
      expect(event.payload['isOwner'], isFalse);
      expect(event.payload.containsKey('avatarUrl'), isFalse);
      expect(
        jsonEncode(event.payload),
        isNot(contains('private@example.test')),
      );
      sender['user_id'] = 7;
      expect(
        KickWebhookEvent.decode('chat.message.sent', body).payload['isOwner'],
        isTrue,
      );
      expect(
        () => KickWebhookEvent.decode('moderation.banned', body),
        throwsFormatException,
      );
    },
  );

  test(
    'real loopback receiver authenticates, binds and deduplicates delivery',
    () async {
      final events = <KickWebhookEvent>[];
      final verifier = KickWebhookSignatureVerifier(
        loadPublicKey: () async => key.pem,
        now: () => now,
      );
      final receiver = KickWebhookReceiver(
        broadcasterId: 7,
        verifier: verifier,
        onEvent: events.add,
        now: () => now,
      );
      addTearDown(receiver.close);
      receiver.setSubscriptions({'subscription': 'chat.message.sent'});
      final port = await receiver.start(port: 0);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<int> send(
        String id,
        Map<String, dynamic> payload, {
        String? signature,
        String subscription = 'subscription',
        String path = '/kick/webhook',
        String type = 'chat.message.sent',
      }) async {
        final bytes = utf8.encode(jsonEncode(payload));
        final timestamp = now.toIso8601String();
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port$path'),
        );
        request.headers.set('Kick-Event-Message-Id', id);
        request.headers.set('Kick-Event-Message-Timestamp', timestamp);
        request.headers.set(
          'Kick-Event-Signature',
          signature ?? key.sign(id, timestamp, bytes),
        );
        request.headers.set('Kick-Event-Subscription-Id', subscription);
        request.headers.set('Kick-Event-Type', type);
        request.headers.set('Kick-Event-Version', '1');
        request.add(bytes);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await send('one', _chat()), 204);
      expect(await send('one', _chat()), 204);
      // Same logical message redelivered with a different delivery ID.
      expect(await send('two', _chat()), 204);
      expect(events, hasLength(1));
      expect(
        await send(
          'three',
          _chat('other'),
          signature: base64Encode(List.filled(256, 0)),
        ),
        403,
      );
      expect(await send('four', _chat('other'), subscription: 'foreign'), 204);
      expect(
        await send('five', _chat('other'), type: 'moderation.banned'),
        204,
      );
      final foreign = _chat('foreign')..['broadcaster'] = {'user_id': 99};
      expect(await send('six', foreign), 204);
      expect(await send('seven', _chat('other'), path: '/api/settings'), 404);
      expect(
        await send('eight', _chat('other'), path: '/kick/webhook?x=1'),
        404,
      );
      expect(events, hasLength(1));
      expect(await send('nine', _chat('other')), 204);
      expect(events, hasLength(2));
    },
  );

  test(
    'failed event admission remains retryable and live replay keys stay bounded',
    () async {
      var fail = true;
      var count = 0;
      final receiver = KickWebhookReceiver(
        broadcasterId: 7,
        verifier: KickWebhookSignatureVerifier(
          loadPublicKey: () async => key.pem,
          now: () => now,
        ),
        onEvent: (_) {
          if (fail) throw StateError('full');
          count++;
        },
        now: () => now,
        replayCapacity: 2,
      )..setSubscriptions({'subscription': 'chat.message.sent'});
      addTearDown(receiver.close);
      final port = await receiver.start(port: 0);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<int> send(String id) async {
        final body = utf8.encode(jsonEncode(_chat(id)));
        final timestamp = now.toIso8601String();
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/kick/webhook'),
        );
        for (final entry in {
          'Kick-Event-Message-Id': id,
          'Kick-Event-Message-Timestamp': timestamp,
          'Kick-Event-Signature': key.sign(id, timestamp, body),
          'Kick-Event-Subscription-Id': 'subscription',
          'Kick-Event-Type': 'chat.message.sent',
          'Kick-Event-Version': '1',
        }.entries) {
          request.headers.set(entry.key, entry.value);
        }
        request.add(body);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await send('one'), 503);
      fail = false;
      expect(await send('one'), 204);
      expect(await send('two'), 503);
      expect(await send('one'), 204);
      expect(count, 1);
    },
  );
}

Map<String, dynamic> _chat([String message = 'message']) => {
  'message_id': message,
  'content': 'Hello 🎮',
  'created_at': '2026-11-15T12:00:00Z',
  'broadcaster': {'user_id': 7},
  'sender': {'user_id': 8, 'username': 'Viewer', 'identity': null},
};

// Generated only in the test process. No production or committed private key.
final class _SigningKey {
  _SigningKey(int seed) {
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List.generate(32, (i) => (seed + i) % 256)),
        ),
      );
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    _private = pair.privateKey;
    final public = pair.publicKey;
    final integers = ASN1Sequence(
      elements: [ASN1Integer(public.modulus), ASN1Integer(public.exponent)],
    ).encode();
    final spki = ASN1Sequence(
      elements: [
        ASN1Sequence(
          elements: [
            ASN1ObjectIdentifier.fromName('rsaEncryption'),
            ASN1Null(),
          ],
        ),
        ASN1BitString(stringValues: integers),
      ],
    ).encode();
    pem =
        '-----BEGIN PUBLIC KEY-----\n${base64Encode(spki)}\n-----END PUBLIC KEY-----';
  }

  late final RSAPrivateKey _private;
  late final String pem;

  String sign(String id, String timestamp, List<int> body) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(_private));
    return base64Encode(
      signer
          .generateSignature(
            Uint8List.fromList([...utf8.encode('$id.$timestamp.'), ...body]),
          )
          .bytes,
    );
  }
}
