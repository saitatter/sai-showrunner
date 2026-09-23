import '../../schema/update.dart';

enum UpdateStatusTone { current, available, error, muted }

final class UpdateStatusView {
  const UpdateStatusView({
    required this.title,
    required this.detail,
    required this.latestVersionLabel,
    required this.tone,
  });

  final String title;
  final String detail;
  final String latestVersionLabel;
  final UpdateStatusTone tone;
}

UpdateStatusView updateStatusView(UpdateInfo? status, {bool checking = false}) {
  final currentVersion = status?.currentVersion;
  final latestVersion = status?.latestVersion.trim() ?? '';
  final checked = status?.checkedAt != null;
  final canCheck = status?.canCheckForUpdates ?? true;
  final latestVersionLabel =
      !checked ||
          latestVersion.isEmpty ||
          !canCheck ||
          status?.status == UpdateStatus.error
      ? 'unknown'
      : 'v$latestVersion';

  if (checking) {
    return UpdateStatusView(
      title: 'Checking for updates',
      detail: 'Contacting GitHub Releases to check for a newer version.',
      latestVersionLabel: latestVersionLabel,
      tone: UpdateStatusTone.muted,
    );
  }
  if (status?.errorMessage != null) {
    return UpdateStatusView(
      title: 'Update check failed',
      detail: _friendlyUpdateError(status!.errorMessage!),
      latestVersionLabel: latestVersionLabel,
      tone: UpdateStatusTone.error,
    );
  }
  if (status != null && !status.canCheckForUpdates) {
    return UpdateStatusView(
      title: 'Development build',
      detail:
          status.message ?? 'Update checks are not available in this build.',
      latestVersionLabel: latestVersionLabel,
      tone: UpdateStatusTone.muted,
    );
  }
  if (status?.downloaded == true) {
    return UpdateStatusView(
      title: 'Update downloaded',
      detail: 'The update is downloaded and ready to install on restart.',
      latestVersionLabel: latestVersionLabel,
      tone: UpdateStatusTone.available,
    );
  }
  if (status?.hasUpdate == true) {
    return UpdateStatusView(
      title: 'Update available',
      detail: 'v$currentVersion → v$latestVersion',
      latestVersionLabel: latestVersionLabel,
      tone: UpdateStatusTone.available,
    );
  }
  if (checked) {
    return UpdateStatusView(
      title: "You're up to date",
      detail: 'ShowRunner v$currentVersion is the current installed version.',
      latestVersionLabel: latestVersionLabel,
      tone: UpdateStatusTone.current,
    );
  }
  return UpdateStatusView(
    title: 'Ready to check',
    detail:
        'Check GitHub Releases to compare this build with the latest update.',
    latestVersionLabel: latestVersionLabel,
    tone: UpdateStatusTone.current,
  );
}

String _friendlyUpdateError(String error) {
  if (RegExp(
    r'\b(ENOTFOUND|ECONNRESET|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|network|offline)\b',
    caseSensitive: false,
  ).hasMatch(error)) {
    return 'Could not reach the update server. Check your internet connection and try again.';
  }
  return error;
}
