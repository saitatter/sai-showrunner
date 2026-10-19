import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/support/support_workspaces.dart';
import 'package:showrunner_flutter/services/update_check_service.dart';

void main() {
  testWidgets('renders the standalone about surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AboutWorkspace())),
    );

    expect(find.text('About ShowRunner'), findsOneWidget);
    expect(find.text('v2.0.0'), findsOneWidget);
    expect(find.text('ShowRunner GitHub'), findsOneWidget);
    expect(find.text('Upstream Project'), findsOneWidget);
    expect(find.text('Help Discord'), findsNothing);
    expect(find.text('License'), findsOneWidget);
  });

  testWidgets('checks for updates on open and renders release details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateWorkspace(
            updateService: UpdateCheckService(
              currentVersion: '1.0.0',
              clock: () => DateTime(2026, 9, 23, 6, 17),
              fetcher: () async => {
                'tag_name': 'v1.1.0',
                'body': '**Fixes** [details](https://example.test)',
                'html_url': 'https://example.test/release',
                'assets': [
                  {
                    'name': 'ShowRunner-Flutter-windows-1.1.0.zip',
                    'browser_download_url':
                        'https://example.test/showrunner.zip',
                    'digest':
                        'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current version: v1.0.0'), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('v1.1.0'), findsOneWidget);
    expect(find.text('Fixes details'), findsOneWidget);
    expect(find.text('Open release page'), findsOneWidget);
    expect(find.text('Download Windows ZIP'), findsOneWidget);
    expect(find.text('Release Notes'), findsOneWidget);
    expect(find.textContaining('Last checked'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('update-workspace-content')))
          .width,
      980,
    );
    final headerRow = find.byKey(const ValueKey('update-header-row'));
    expect(headerRow, findsOneWidget);
    expect(
      find.descendant(of: headerRow, matching: find.text('Updates')),
      findsOneWidget,
    );
  });

  testWidgets('does not offer a download without a valid release checksum', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateWorkspace(
            updateService: UpdateCheckService(
              currentVersion: '1.0.0',
              fetcher: () async => {
                'tag_name': 'v1.1.0',
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
    await tester.pumpAndSettle();

    expect(find.text('Download Windows ZIP'), findsNothing);
    expect(
      find.text(
        'Download unavailable: this release has no valid SHA-256 checksum.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open release page'), findsOneWidget);
  });

  testWidgets('renders offline update errors without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateWorkspace(
            updateService: UpdateCheckService(
              currentVersion: '1.0.0',
              fetcher: () async => throw const SocketException('offline'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Update check failed'), findsOneWidget);
    expect(find.textContaining('internet connection'), findsOneWidget);
    expect(find.text('unknown'), findsOneWidget);
  });

  testWidgets('keeps an empty release-notes panel before the check finishes', (
    tester,
  ) async {
    final release = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateWorkspace(
            updateService: UpdateCheckService(
              currentVersion: '2.0.0',
              fetcher: () => release.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Release Notes'), findsOneWidget);
    expect(
      find.text('Release notes will appear here after checking for updates.'),
      findsOneWidget,
    );
    expect(find.text('unknown'), findsOneWidget);

    release.complete({'tag_name': 'v2.0.0', 'body': ''});
    await tester.pumpAndSettle();
    expect(find.text("You're up to date"), findsOneWidget);
  });
}
