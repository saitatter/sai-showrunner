import 'actions.dart';
import 'contracts.dart';
import 'webhook_receiver.dart';
import 'webhook_signature.dart';

/// Owns the dedicated listener and only subscriptions created by this session.
/// Existing subscriptions are reused, never removed on another owner's behalf.
final class KickEventWorker {
  KickEventWorker({
    required this.request,
    required this.loadPublicKey,
    required this.broadcasterId,
    required this.publicWebhookUrl,
    required this.onEvent,
    this.port = 53544,
    this.onStateChanged,
  });

  final KickRequest request;
  final KickPublicKeyLoader loadPublicKey;
  final int broadcasterId;
  final String publicWebhookUrl;
  final int port;
  final void Function(KickWebhookEvent) onEvent;
  final void Function()? onStateChanged;
  final _created = <String>{};
  KickWebhookReceiver? _receiver;
  Future<void>? _starting;
  Future<void>? _stopping;
  bool _closed = false;
  bool _ready = false;
  String state = 'stopped';

  Future<void> start() {
    if (_closed) return Future.error(StateError('Kick worker is closed.'));
    if (_ready) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    _state('connecting');
    try {
      _requireOpen();
      kickUserId(broadcasterId, 'broadcasterId');
      final url = Uri.tryParse(publicWebhookUrl);
      if (url == null ||
          url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          url.path != '/kick/webhook' ||
          url.hasQuery ||
          url.hasFragment) {
        throw ArgumentError(
          'Register a public HTTPS /kick/webhook URL in Kick Developer.',
        );
      }
      if (port < 0 || port > 65535) {
        throw ArgumentError('Invalid webhook port.');
      }
      final response = await request('GET', '/public/v1/users', const {}, null);
      _requireOpen();
      final users = response['data'];
      if (users is! List ||
          users.length != 1 ||
          users.single is! Map ||
          kickUserId((users.single as Map)['user_id'], 'userId') !=
              broadcasterId) {
        throw StateError(
          'Connect the Kick broadcaster account to receive its chat.',
        );
      }
      final receiver = KickWebhookReceiver(
        broadcasterId: broadcasterId,
        verifier: KickWebhookSignatureVerifier(loadPublicKey: loadPublicKey),
        onEvent: (event) {
          if (_closed || !_ready) {
            throw StateError('Kick listener is not ready.');
          }
          onEvent(event);
        },
      );
      _receiver = receiver;
      await receiver.start(port: port);
      _requireOpen();
      final existing = await request('GET', '/public/v1/events/subscriptions', {
        'broadcaster_user_id': broadcasterId,
      }, null);
      _requireOpen();
      final rows = existing['data'];
      if (rows is! List || rows.length > 1000) {
        throw const FormatException('Kick returned invalid subscriptions.');
      }
      const types = {'chat.message.sent', 'moderation.banned'};
      final bindings = <String, String>{};
      for (final row in rows) {
        if (row is! Map ||
            row['method'] != 'webhook' ||
            row['version'] != 1 ||
            row['broadcaster_user_id'] != broadcasterId ||
            !types.contains(row['event'])) {
          continue;
        }
        bindings[kickMessageId(row['id'])] = row['event'] as String;
      }
      final missing = types.difference(bindings.values.toSet());
      if (missing.isNotEmpty) {
        final created = await request(
          'POST',
          '/public/v1/events/subscriptions',
          const {},
          {
            'method': 'webhook',
            // For user tokens Kick infers the broadcaster from the token.
            'events': [
              for (final name in missing) {'name': name, 'version': 1},
            ],
          },
        );
        final results = created['data'];
        if (results is! List || results.length > types.length) {
          throw const FormatException(
            'Kick returned invalid subscription results.',
          );
        }
        for (final result in results) {
          if (result is! Map ||
              result['version'] != 1 ||
              !missing.contains(result['name'])) {
            continue;
          }
          final id = result['subscription_id'];
          if (id is String && id.isNotEmpty) {
            final validId = kickMessageId(id);
            _created.add(validId);
            bindings[validId] = result['name'] as String;
          }
        }
        _requireOpen();
        if (!bindings.values.toSet().containsAll(types)) {
          throw StateError('Kick did not subscribe to all chat events.');
        }
      }
      receiver.setSubscriptions(bindings);
      _ready = true;
      // Listening locally cannot prove that a public tunnel is reachable.
      _state('listening');
    } catch (_) {
      _ready = false;
      await _receiver?.close();
      _receiver = null;
      await _removeOwnedSubscriptions();
      if (!_closed) _state('error');
      rethrow;
    }
  }

  void _requireOpen() {
    if (_closed) throw StateError('Kick worker is stopped.');
  }

  void _state(String value) {
    state = value;
    onStateChanged?.call();
  }

  Future<void> stop() {
    _closed = true;
    _ready = false;
    return _stopping ??= _stop();
  }

  Future<void> _stop() async {
    await _receiver?.close();
    try {
      await _starting;
    } catch (_) {
      /* Startup owns partial cleanup. */
    }
    await _removeOwnedSubscriptions();
    _receiver = null;
    _state('stopped');
  }

  Future<void> _removeOwnedSubscriptions() async {
    if (_created.isEmpty) return;
    final ids = _created.toList(growable: false);
    _created.clear();
    try {
      await request('DELETE', '/public/v1/events/subscriptions', {
        'id': ids,
      }, null);
    } catch (_) {
      // A network failure must not keep the local listener alive. A subsequent
      // start reuses orphaned subscriptions; foreign IDs are never deleted.
    }
  }
}
