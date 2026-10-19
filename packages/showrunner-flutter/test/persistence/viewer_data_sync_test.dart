import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/persistence/viewer_data_sync.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test(
    'syncs Twitch viewer identities and preserves existing values',
    () async {
      final repository = InMemoryViewerDataRepository(
        definitions: [
          const ViewerVariableDefinition(
            name: 'points',
            type: 'number',
            defaultValue: 0,
          ),
        ],
      );
      final hub = DartPluginEventHub();
      final synchronizer = ViewerDataSynchronizer(
        repository: repository,
        eventHub: hub,
      );
      final added = <dynamic>[];
      final changed = <dynamic>[];
      final addedSubscription = hub.stream('viewerDataAdded').listen(added.add);
      final changedSubscription = hub
          .stream('viewerDataChanged')
          .listen(changed.add);

      final first = await synchronizer.syncEvent('follow', {
        'user_id': '42',
        'user_name': 'Alice',
      });
      expect(first?.created, isTrue);
      expect(
        (await repository.loadViewer(
          'twitch',
          const ViewerIdentity(id: '42', displayName: 'Alice'),
        )).viewer.displayName,
        'Alice',
      );
      await Future<void>.delayed(Duration.zero);
      expect(added, hasLength(1));

      await repository.setViewerValue(
        'twitch',
        const ViewerIdentity(id: '42', displayName: 'Alice'),
        'points',
        12,
      );
      final renamed = await synchronizer.syncEvent('chat', {
        'chatter_user_id': '42',
        'chatter_user_name': 'AliceUpdated',
      });
      expect(renamed?.created, isFalse);
      expect(renamed?.changed, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(changed, hasLength(1));
      final row = await repository.loadViewer(
        'twitch',
        const ViewerIdentity(id: '42', displayName: 'AliceUpdated'),
      );
      expect(row.viewer.displayName, 'AliceUpdated');
      expect(row.values['points'], 12);

      await addedSubscription.cancel();
      await changedSubscription.cancel();
      await hub.dispose();
    },
  );

  test(
    'syncs YouTube authors and ignores anonymous or incomplete events',
    () async {
      final repository = InMemoryViewerDataRepository();
      final hub = DartPluginEventHub();
      final synchronizer = ViewerDataSynchronizer(
        repository: repository,
        eventHub: hub,
      );

      final youtube = await synchronizer.syncEvent('chatMessage', {
        'authorDetails': {'channelId': 'yt-7', 'displayName': 'YouTube Viewer'},
      });
      expect(youtube?.row.provider, 'youtube');
      expect(youtube?.row.viewer.displayName, 'YouTube Viewer');
      expect(
        (await repository.queryViewers('youtube')).single.viewer.id,
        'yt-7',
      );
      expect(
        await synchronizer.syncEvent('bits', {
          'is_anonymous': true,
          'user_id': 'hidden',
          'user_name': 'Hidden',
        }),
        isNull,
      );
      expect(
        await synchronizer.syncEvent('chat', {'message_id': 'missing-user'}),
        isNull,
      );
      await hub.dispose();
    },
  );

  test('start subscribes to provider events and stop detaches them', () async {
    final repository = InMemoryViewerDataRepository();
    final hub = DartPluginEventHub();
    final synchronizer = ViewerDataSynchronizer(
      repository: repository,
      eventHub: hub,
    );
    await synchronizer.start();
    expect(synchronizer.isRunning, isTrue);
    hub.emit('follow', {'user_id': '1', 'user_name': 'Viewer'});
    await Future<void>.delayed(Duration.zero);
    expect(await repository.queryViewers('twitch'), hasLength(1));
    await synchronizer.stop();
    expect(synchronizer.isRunning, isFalse);
    hub.emit('follow', {'user_id': '2', 'user_name': 'Ignored'});
    await Future<void>.delayed(Duration.zero);
    expect(await repository.queryViewers('twitch'), hasLength(1));
    await hub.dispose();
  });
}
