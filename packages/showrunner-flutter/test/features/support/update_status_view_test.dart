import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/support/update_status_view.dart';
import 'package:showrunner_flutter/schema/update.dart';

void main() {
  test('shows unknown latest version before the first check', () {
    final view = updateStatusView(
      const UpdateInfo(
        currentVersion: '2.0.0',
        latestVersion: '2.0.0',
        hasUpdate: false,
      ),
    );

    expect(view.title, 'Ready to check');
    expect(view.latestVersionLabel, 'unknown');
    expect(view.tone, UpdateStatusTone.current);
  });

  test(
    'shows the installed and latest versions when an update is available',
    () {
      final view = updateStatusView(
        const UpdateInfo(
          currentVersion: '2.0.0',
          latestVersion: '2.1.0',
          hasUpdate: true,
          status: UpdateStatus.available,
          checkedAt: '2026-09-23T09:00:00Z',
        ),
      );

      expect(view.title, 'Update available');
      expect(view.detail, 'v2.0.0 → v2.1.0');
      expect(view.latestVersionLabel, 'v2.1.0');
      expect(view.tone, UpdateStatusTone.available);
    },
  );

  test('shows a concise offline error and keeps latest version unknown', () {
    final view = updateStatusView(
      const UpdateInfo(
        currentVersion: '2.0.0',
        latestVersion: '2.0.0',
        hasUpdate: false,
        status: UpdateStatus.error,
        errorMessage: 'Update check is offline.',
        checkedAt: '2026-09-23T09:00:00Z',
      ),
    );

    expect(view.title, 'Update check failed');
    expect(view.detail, contains('internet connection'));
    expect(view.latestVersionLabel, 'unknown');
    expect(view.tone, UpdateStatusTone.error);
  });
}
