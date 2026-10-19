import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mounts the deterministic navigation rail shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationRail(
            selectedIndex: 0,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.account_tree),
                label: Text('Graph'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.extension),
                label: Text('Plugins'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.monitor_heart),
                label: Text('Diagnostics'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bolt),
                label: Text('Automations'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_alt),
                label: Text('Profiles'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.layers),
                label: Text('Resources'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long),
                label: Text('Logs'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.info),
                label: Text('About'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rocket_launch),
                label: Text('Setup'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.text('Resources'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
