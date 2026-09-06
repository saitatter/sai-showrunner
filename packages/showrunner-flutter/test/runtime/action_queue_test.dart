import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/persistence/queue_repository.dart';
import 'package:showrunner_flutter/domain/errors/showrunner_error.dart';
import 'package:showrunner_flutter/plugins/contracts/identifiers.dart';

void main() {
  test('processes, pauses, replays, and bounds Dart queue history', () async {
    final queue = DartActionQueue(historyLimit: 2);
    final first = queue.enqueue({'type': 'manual'}, {'value': 1});
    final second = queue.enqueue({'type': 'manual'}, {'value': 2});
    queue.enqueue({'type': 'manual'}, {'value': 3});
    queue.paused = true;
    await queue.processNext((item) async => null);
    expect(queue.pending, hasLength(3));
    queue.paused = false;
    await queue.processNext((item) async => null);
    await queue.processNext((item) async => null);
    expect(queue.history.map((item) => item.id), [second.id, first.id]);
    queue.clearPending();
    queue.replay(first.id);
    expect(queue.pending.single.contextState, {'value': 1});
    queue.skip(queue.pending.single.id);
    expect(queue.pending, isEmpty);
  });

  test('cancels running queue work and times out bounded executions', () async {
    final queue = DartActionQueue(
      defaultTimeout: const Duration(milliseconds: 10),
    );
    final started = Completer<void>();
    var cancelled = false;
    DartCancellationToken? token;
    queue.enqueue({'type': 'manual'}, {});

    final processing = queue.processNext((item) async {
      started.complete();
      token = queue.runningCancellationToken;
      await Future<void>.delayed(const Duration(seconds: 1));
      return null;
    }, cancelRunning: () async => cancelled = true);
    await started.future;
    await queue.cancelRunning();
    await expectLater(processing, throwsA(isA<TimeoutException>()));
    expect(cancelled, isTrue);
    expect(token?.isCancelled, isTrue);
    expect(queue.running, isNull);
  });

  test('records skipped pending work with an operator reason', () {
    final queue = DartActionQueue();
    final item = queue.enqueue({'type': 'manual'}, {});

    queue.skip(item.id);

    expect(queue.pending, isEmpty);
    expect(queue.history.single.status, 'skipped');
    expect(queue.history.single.reason, 'Skipped by operator');
    expect(queue.history.single.completedAt, isNotNull);
  });

  test('records typed action error metadata in queue history', () async {
    final queue = DartActionQueue();
    queue.enqueue({'type': 'graph'}, {});

    await expectLater(
      queue.processNext((item) async {
        throw const ActionExecutionError(
          pluginId: PluginId('obs'),
          operationId: 'scene',
          technicalMessage: 'OBS action failed.',
          userMessage: 'OBS could not switch the scene.',
          retryable: true,
        );
      }),
      throwsA(isA<ActionExecutionError>()),
    );

    final item = queue.history.single;
    expect(item.errorCode, 'action.execution');
    expect(item.errorUserMessage, 'OBS could not switch the scene.');
    expect(item.errorPluginId, 'obs');
    expect(item.errorOperationId, 'scene');
    expect(item.errorRetryable, isTrue);
    await queue.dispose();
  });

  test(
    'records cancelled running work after the cancel callback completes',
    () async {
      final queue = DartActionQueue();
      final started = Completer<void>();
      final release = Completer<void>();
      queue.enqueue({'type': 'manual'}, {});

      final processing = queue.processNext((item) async {
        started.complete();
        await release.future;
        return null;
      }, cancelRunning: () async => release.complete());
      await started.future;
      await queue.cancelRunning();
      await processing;

      expect(queue.history.single.status, 'cancelled');
      expect(queue.history.single.reason, 'Cancelled by operator');
    },
  );

  test('publishes queue changes for enqueue, start, and completion', () async {
    final queue = DartActionQueue();
    final changes = <String>[];
    final subscription = queue.changes.listen(
      (item) => changes.add(item?.id ?? 'idle'),
    );
    queue.enqueue({'type': 'manual'}, {});
    await queue.processNext((item) async => null);
    await Future<void>.delayed(Duration.zero);
    expect(changes, ['queue-0', 'queue-0', 'idle']);
    await subscription.cancel();
    await queue.dispose();
  });

  test('persists and restores pending queue work', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-queue-',
    );
    final file = File('${directory.path}/queue.json');
    final source = DartActionQueue(historyLimit: 3);
    source.enqueue({'type': 'graph'}, {'value': 42});
    await QueueRepository(file).save(source);

    final restored = DartActionQueue(historyLimit: 3);
    await QueueRepository(file).load(restored);

    expect(restored.pending.single.source, {'type': 'graph'});
    expect(restored.pending.single.contextState, {'value': 42});
    await directory.delete(recursive: true);
  });
}
