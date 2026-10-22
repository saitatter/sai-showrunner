import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/remote/remote_workspace.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'late discovery failure cannot replace newer results or leak payloads',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('remote-view-'),
      ))!;
      final data = ShowRunnerDataService(root);
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final first = Completer<List<RemoteDashboardInfo>>(),
          second = Completer<List<RemoteDashboardInfo>>();
      var loads = 0;
      Future<List<RemoteDashboardInfo>> load() =>
          ++loads == 1 ? first.future : second.future;
      Widget app() => MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(dataService: data, discoverDashboards: load),
        ),
      );
      await tester.pumpWidget(app());
      await tester.tap(find.text('Refresh'));
      second.complete(const [
        RemoteDashboardInfo(
          ownerId: 'owner',
          dashboardId: 'current',
          name: 'Current dashboard',
        ),
      ]);
      await tester.pumpAndSettle();
      first.completeError(StateError('private-server-marker'));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Current dashboard'), findsOneWidget);
      expect(find.text('Remote dashboard discovery failed'), findsNothing);
      expect(find.textContaining('private-server-marker'), findsNothing);
      expect(loads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
