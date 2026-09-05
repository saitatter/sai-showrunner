import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/support/support_workspaces.dart';
import 'package:showrunner_flutter/services/update_check_service.dart';

void main() {
  testWidgets('renders fetched release details and notes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutWorkspace(
            updateService: UpdateCheckService(
              currentVersion: '1.0.0',
              fetcher: () async => {
                'tag_name': 'v1.1.0',
                'body': '**Fixes** [details](https://example.test)',
                'html_url': 'https://example.test/release',
                'assets': [
                  {
                    'name': 'ShowRunner-Flutter-windows-1.1.0.zip',
                    'browser_download_url':
                        'https://example.test/showrunner.zip',
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check for Updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Update available: 1.1.0'), findsOneWidget);
    expect(find.text('Fixes details'), findsOneWidget);
    expect(find.text('Open release page'), findsOneWidget);
    expect(find.text('Download Windows ZIP'), findsOneWidget);
  });

  testWidgets('renders offline update errors without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutWorkspace(
            updateService: UpdateCheckService(
              currentVersion: '1.0.0',
              fetcher: () async => throw const SocketException('offline'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check for Updates'));
    await tester.pumpAndSettle();

    expect(find.text('Update check is offline.'), findsOneWidget);
  });
}
