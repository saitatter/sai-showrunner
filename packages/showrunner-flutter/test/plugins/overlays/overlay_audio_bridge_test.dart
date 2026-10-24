import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_audio_bridge.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';

void main() {
  testWidgets(
    'cancellation and playback IDs are isolated by overlay and cancel timers',
    (tester) async {
      final sent = <(String, String)>[];
      final bridge = OverlayAudioBridge(
        resolveMedia: (_, id) async => '/overlays/$id/media/fixture.wav',
        send: (id, name, args) async {
          sent.add((id, name));
          return true;
        },
      );
      var firstDone = false, secondDone = false;
      final first = bridge
          .playAudio(
            'first',
            const SoundPlayRequest(
              file: 'fixture',
              playId: 'shared',
              endSec: 30,
            ),
          )
          .then((value) {
            firstDone = true;
            return value;
          });
      final second = bridge
          .playAudio(
            'second',
            const SoundPlayRequest(
              file: 'fixture',
              playId: 'shared',
              endSec: 30,
            ),
          )
          .then((value) {
            secondDone = true;
            return value;
          });
      await tester.pump();
      expect(sent, [
        ('first', 'overlays_playAudio'),
        ('second', 'overlays_playAudio'),
      ]);
      await bridge.cancelAudio('first', 'shared');
      await tester.pump();
      expect(firstDone, isTrue);
      expect(secondDone, isFalse);
      await bridge.cancelAudio('second', 'shared');
      await tester.pump();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(secondDone, isTrue);
      await bridge.close();
      // testWidgets also rejects leftover duration timers at teardown.
    },
  );

  testWidgets(
    'rejects duplicate and excess playback and drains all timers on close',
    (tester) async {
      final bridge = OverlayAudioBridge(
        resolveMedia: (_, id) async => '/overlays/$id/media/fixture.wav',
        send: (_, _, _) async => true,
      );
      final work = [
        for (var index = 0; index < 64; index++)
          bridge.playAudio(
            'fixture',
            SoundPlayRequest(file: 'fixture', playId: '$index', endSec: 60),
          ),
      ];
      expect(
        await bridge.playAudio(
          'fixture',
          const SoundPlayRequest(
            file: 'fixture',
            playId: 'overflow',
            endSec: 60,
          ),
        ),
        isFalse,
      );
      await tester.pump();
      final closing = bridge.close();
      expect(identical(closing, bridge.close()), isTrue);
      await closing;
      expect(await Future.wait(work), everyElement(isFalse));
      expect(
        await bridge.playAudio(
          'fixture',
          const SoundPlayRequest(file: 'fixture'),
        ),
        isFalse,
      );

      final duplicate = OverlayAudioBridge(
        resolveMedia: (_, id) async => '/overlays/$id/media/fixture.wav',
        send: (_, _, _) async => true,
      );
      final original = duplicate.playAudio(
        'fixture',
        const SoundPlayRequest(file: 'fixture', playId: 'same', endSec: 60),
      );
      expect(
        await duplicate.playAudio(
          'fixture',
          const SoundPlayRequest(file: 'fixture', playId: 'same', endSec: 60),
        ),
        isFalse,
      );
      await duplicate.close();
      expect(await original, isFalse);
    },
  );

  testWidgets('shutdown waits for owned work and suppresses late media sends', (
    tester,
  ) async {
    final resolved = Completer<String?>();
    var sent = 0;
    final bridge = OverlayAudioBridge(
      resolveMedia: (_, _) => resolved.future,
      send: (_, _, _) async {
        sent++;
        return true;
      },
    );
    final playing = bridge.playAudio(
      'fixture',
      const SoundPlayRequest(file: 'fixture'),
    );
    var closed = false;
    final closing = bridge.close().then((_) {
      closed = true;
    });
    await tester.pump();
    expect(closed, isFalse);
    resolved.complete('/overlays/fixture/media/fixture.wav');
    expect(await playing, isFalse);
    await closing;
    expect(sent, 0);
    expect(closed, isTrue);
  });
}
