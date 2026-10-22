import 'dart:async';
import 'package:flutter/material.dart';
import '../../../runtime/expression.dart';

@immutable
class TwitchChatActivityView {
  const TwitchChatActivityView({
    this.author,
    this.message,
    this.history = const [],
  });
  final String? author, message;
  final List<String> history;
}

/// Borrows provider events; never starts a provider worker or loads account data.
class TwitchChatActivityController
    extends ValueNotifier<TwitchChatActivityView> {
  TwitchChatActivityController(Stream<RuntimeMap> stream)
    : super(const TwitchChatActivityView()) {
    configure(stream);
  }
  StreamSubscription<RuntimeMap>? _subscription;
  final _cancellations = <Future<void>>[];
  Object _generation = Object();
  bool _disposed = false;
  void _cancel() {
    final future = _subscription?.cancel();
    _subscription = null;
    if (future != null) {
      _cancellations.add(future);
      unawaited(
        future.then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
      );
    }
  }

  void configure(Stream<RuntimeMap> stream) {
    if (_disposed) return;
    _generation = Object();
    final generation = _generation;
    _cancel();
    value = const TwitchChatActivityView();
    _subscription = stream.listen((event) {
      if (_disposed || !identical(generation, _generation)) return;
      final author = event['chatter_user_name']?.toString();
      final message = event['message']?.toString();
      value = TwitchChatActivityView(
        author: author,
        message: message,
        history: List.unmodifiable(
          [
            '${author ?? 'Unknown'}: ${message ?? 'Empty message'}',
            ...value.history,
          ].take(20),
        ),
      );
    });
  }

  Future<void> close() async {
    dispose();
    await Future.wait(_cancellations);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancel();
    super.dispose();
  }
}

class TwitchChatSummary extends StatelessWidget {
  const TwitchChatSummary({super.key, required this.activity});
  final TwitchChatActivityController activity;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TwitchChatActivityView>(
        valueListenable: activity,
        builder: (context, view, _) => Card(
          child: ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(view.message ?? 'No Twitch chat messages yet'),
            subtitle: Text(view.author ?? 'Latest Twitch message'),
          ),
        ),
      );
}

class TwitchChatHistory extends StatelessWidget {
  const TwitchChatHistory({super.key, required this.activity});
  final TwitchChatActivityController activity;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TwitchChatActivityView>(
        valueListenable: activity,
        builder: (context, view, _) => view.history.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final message in view.history)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.chat_outlined),
                      title: Text(message),
                    ),
                ],
              ),
      );
}
