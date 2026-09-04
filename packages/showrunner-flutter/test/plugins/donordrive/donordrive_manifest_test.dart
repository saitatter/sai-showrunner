import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/donordrive/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test(
    'polls donations and emits donation, incentive, and milestone events',
    () async {
      final eventHub = DartPluginEventHub();
      final calls = <String>[];
      var poll = 0;
      final runtime = DonorDriveRuntime(
        transport: DonorDriveTransport((path, query) async {
          calls.add('$path ${query.keys.join(',')}');
          if (path.endsWith('/donations')) {
            return poll == 1
                ? [
                    {
                      'displayName': 'Alice',
                      'amount': 50,
                      'incentiveID': 'shirt',
                      'message': 'Keep going!',
                    },
                  ]
                : const [];
          }
          if (path.endsWith('/milestones')) {
            return [
              {
                'milestoneID': 'goal-1',
                'description': 'First goal',
                'fundraisingGoal': 100,
              },
            ];
          }
          return {
            'eventName': 'Test Event',
            'fundraisingGoal': 1000,
            'sumDonations': poll == 0 ? 50 : 150,
            'sumPledges': 0,
            'numDonations': poll,
          };
        }),
        eventHub: eventHub,
        apiBase: 'https://example.test/api',
        participantId: '123',
      );
      final donations = <dynamic>[];
      final incentives = <dynamic>[];
      final milestones = <dynamic>[];
      final donationSub = eventHub.stream('donation').listen(donations.add);
      final incentiveSub = eventHub.stream('incentive').listen(incentives.add);
      final milestoneSub = eventHub.stream('milestone').listen(milestones.add);

      await runtime.poll();
      poll = 1;
      await runtime.poll();
      await Future<void>.delayed(Duration.zero);

      expect(calls, [
        '/participants/123 ',
        '/participants/123 ',
        '/participants/123/donations where,orderBy',
        '/participants/123/milestones ',
      ]);
      expect(donations.single['donor'], 'Alice');
      expect(incentives.single['incentiveId'], 'shirt');
      expect(milestones.single, {
        'milestoneId': 'goal-1',
        'milestone': 'First goal',
        'amount': 100,
      });

      await donationSub.cancel();
      await incentiveSub.cancel();
      await milestoneSub.cancel();
      await eventHub.dispose();
    },
  );

  test('matches donation filters and configured ids', () async {
    final eventHub = DartPluginEventHub();
    final runtime = DonorDriveRuntime(
      transport: DonorDriveTransport((path, query) async => const {}),
      eventHub: eventHub,
      apiBase: 'https://example.test/api',
      participantId: '123',
    );
    final registry = DartPluginRegistry()
      ..register(createDonorDrivePlugin(runtime));

    final donation = registry.findTrigger('donordrive', 'donation')!;
    final incentive = registry.findTrigger('donordrive', 'incentive')!;
    final milestone = registry.findTrigger('donordrive', 'milestone')!;
    expect(donation.matches!({'minimumAmount': 25}, {'amount': 50}), isTrue);
    expect(
      donation.matches!(
        {'incentive': true},
        {'amount': 50, 'isIncentive': false},
      ),
      isFalse,
    );
    expect(
      incentive.matches!({'incentive': 'shirt'}, {'incentiveId': 'shirt'}),
      isTrue,
    );
    expect(
      milestone.matches!({'milestone': 'goal-2'}, {'milestoneId': 'goal-1'}),
      isFalse,
    );
    runtime.stop();
    await eventHub.dispose();
  });
}
