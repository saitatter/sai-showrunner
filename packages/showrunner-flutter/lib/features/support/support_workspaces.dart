import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../schema/update.dart';
import 'update_status_view.dart';
import '../../services/structured_logger.dart';
import '../../services/update_artifact_service.dart';
import '../../services/update_check_service.dart';
import '../../services/update_install_service.dart';

class LogsWorkspace extends StatefulWidget {
  const LogsWorkspace({super.key});

  @override
  State<LogsWorkspace> createState() => _LogsWorkspaceState();
}

class _LogsWorkspaceState extends State<LogsWorkspace> {
  LogLevel? _filter;

  @override
  Widget build(BuildContext context) {
    final logger = ShowRunnerLogger.instance;
    return StreamBuilder<LogEntry>(
      stream: logger.stream,
      builder: (context, snapshot) {
        final logs = logger.logs
            .where((log) => _filter == null || log.level == _filter)
            .toList()
            .reversed
            .toList();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Text(
                  'Logs & Activity',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                DropdownButton<LogLevel?>(
                  value: _filter,
                  hint: const Text('Filter level'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Levels'),
                    ),
                    ...LogLevel.values.map(
                      (level) => DropdownMenuItem(
                        value: level,
                        child: Text(level.name.toUpperCase()),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _filter = value),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Add test log entry',
                  icon: const Icon(Icons.add_comment),
                  onPressed: () {
                    logger.info(
                      'manual',
                      'Manual log entry triggered at ${DateTime.now()}',
                    );
                    setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Clear log history',
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () {
                    logger.clear();
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (logs.isEmpty)
              const ListTile(
                leading: Icon(Icons.article_outlined),
                title: Text('No log entries recorded'),
              )
            else
              ...logs.map((log) {
                final color = switch (log.level) {
                  LogLevel.debug => Colors.grey,
                  LogLevel.info => Colors.blue,
                  LogLevel.warning => Colors.orange,
                  LogLevel.error => Colors.redAccent,
                };
                return Card(
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.circle, color: color, size: 12),
                    title: Text('[${log.category}] ${log.message}'),
                    subtitle: Text(
                      '${log.timestamp.toIso8601String().substring(11, 19)} · Level: ${log.level.name.toUpperCase()}',
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class AboutWorkspace extends StatelessWidget {
  const AboutWorkspace({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'About ShowRunner',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text('v$showRunnerFlutterVersion'),
      const SizedBox(height: 16),
      _AboutLink(
        label: 'ShowRunner GitHub',
        url: Uri.parse('https://github.com/saitatter/sai-showrunner'),
      ),
      _AboutLink(
        label: 'Upstream Project',
        url: Uri.parse('https://github.com/LordTocs/CastMate'),
      ),
      _AboutLink(
        label: 'License',
        url: Uri.parse(
          'https://github.com/saitatter/sai-showrunner/blob/main/LICENSE.md',
        ),
      ),
    ],
  );
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({required this.label, required this.url});

  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () => _openExternalUrl(url),
      child: Text(label),
    ),
  );
}

Future<void> _openExternalUrl(Uri url) async {
  if (Platform.isWindows) {
    await Process.start('cmd.exe', ['/c', 'start', '', url.toString()]);
  } else if (Platform.isMacOS) {
    await Process.start('open', [url.toString()]);
  } else if (Platform.isLinux) {
    await Process.start('xdg-open', [url.toString()]);
  } else {
    throw UnsupportedError('Opening external links is not supported.');
  }
}

class UpdateWorkspace extends StatefulWidget {
  const UpdateWorkspace({
    super.key,
    this.updateService,
    this.artifactService,
    this.installService,
    this.onRestartRequested,
    this.downloadDirectory,
    this.rollbackDirectory,
  });

  final UpdateCheckService? updateService;
  final UpdateArtifactService? artifactService;
  final UpdateInstallService? installService;
  final Future<bool> Function()? onRestartRequested;
  final Directory? downloadDirectory;
  final Directory? rollbackDirectory;

  @override
  State<UpdateWorkspace> createState() => _UpdateWorkspaceState();
}

class _UpdateWorkspaceState extends State<UpdateWorkspace> {
  late final UpdateCheckService _updateService;
  late UpdateInfo _updateInfo;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  bool _rollbackAvailable = false;
  File? _downloadedArtifact;
  Object? _downloadError;

  @override
  void initState() {
    super.initState();
    _updateService =
        widget.updateService ??
        UpdateCheckService(currentVersion: showRunnerFlutterVersion);
    _updateInfo =
        _updateService.lastResult ??
        const UpdateInfo(
          currentVersion: showRunnerFlutterVersion,
          latestVersion: showRunnerFlutterVersion,
          hasUpdate: false,
        );
    unawaited(_refreshRollbackAvailability());
    if (_updateInfo.checkedAt == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkUpdate());
      });
    }
  }

  Future<void> _refreshRollbackAvailability() async {
    final directory = widget.rollbackDirectory;
    if (directory == null) return;
    final available = await File('${directory.path}/manifest.json').exists();
    if (mounted) setState(() => _rollbackAvailable = available);
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final result = await _updateService.check(force: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateInfo = result;
    });
  }

  Future<void> _openRelease() async {
    final url = _updateInfo.downloadUrl;
    if (url.isEmpty) return;
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  }

  Future<void> _downloadArtifact() async {
    if (_updateInfo.artifactUrl.isEmpty || _downloading) return;
    setState(() {
      _downloading = true;
      _downloadError = null;
      _downloadedArtifact = null;
    });
    try {
      final artifact =
          await (widget.artifactService ?? const UpdateArtifactService())
              .download(
                _updateInfo,
                directory:
                    widget.downloadDirectory ??
                    Directory(
                      '${Directory.systemTemp.path}/ShowRunner-updates',
                    ),
              );
      if (!mounted) return;
      setState(() {
        _downloadedArtifact = artifact;
        _updateInfo = _updateInfo.copyWith(
          status: UpdateStatus.downloaded,
          downloaded: true,
        );
      });
      _updateService.remember(_updateInfo);
    } catch (error) {
      if (mounted) setState(() => _downloadError = error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _installDownloadedArtifact() async {
    final artifact = _downloadedArtifact;
    if (artifact == null || _installing || !Platform.isWindows) return;
    final rollbackDirectory = widget.rollbackDirectory;
    if (rollbackDirectory == null) {
      setState(() => _downloadError = 'Rollback storage is unavailable.');
      return;
    }
    setState(() {
      _installing = true;
      _downloadError = null;
    });
    try {
      final executable = File(Platform.resolvedExecutable);
      await (widget.installService ?? const UpdateInstallService()).install(
        artifact,
        executable: executable,
        installDirectory: executable.parent,
        rollbackDirectory: rollbackDirectory,
        backupVersion: _updateInfo.currentVersion,
      );
      if (!mounted) return;
      _rollbackAvailable = true;
      final restarted = await widget.onRestartRequested?.call() ?? true;
      if (!restarted && mounted) {
        setState(() {
          _installing = false;
          _downloadError = 'Restart canceled.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _downloadError = error;
        });
      }
    }
  }

  Future<void> _downloadAndInstall() async {
    await _downloadArtifact();
    if (mounted && _downloadedArtifact != null && Platform.isWindows) {
      await _installDownloadedArtifact();
    }
  }

  Future<void> _rollbackInstalledUpdate() async {
    final directory = widget.rollbackDirectory;
    if (directory == null || _installing || !Platform.isWindows) return;
    setState(() {
      _installing = true;
      _downloadError = null;
    });
    try {
      final executable = File(Platform.resolvedExecutable);
      await (widget.installService ?? const UpdateInstallService()).rollback(
        executable: executable,
        installDirectory: executable.parent,
        rollbackDirectory: directory,
      );
      if (!mounted) return;
      final restarted = await widget.onRestartRequested?.call() ?? true;
      if (!restarted && mounted) {
        setState(() {
          _installing = false;
          _downloadError = 'Restart canceled.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _downloadError = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = updateStatusView(_updateInfo, checking: _checking);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Updates', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Current version: v${_updateInfo.currentVersion}'),
        const SizedBox(height: 8),
        const Text(
          'SAI ShowRunner — Desktop Stream Engine & Automation Runtime',
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checking || !_updateInfo.canCheckForUpdates
                          ? null
                          : _checkUpdate,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Check for updates'),
                    ),
                    if (_updateInfo.hasUpdate &&
                        Platform.isWindows &&
                        _updateInfo.artifactUrl.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _downloading || _installing
                            ? null
                            : _downloadAndInstall,
                        icon: const Icon(Icons.download),
                        label: const Text('Update and restart'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _updateStatusPanel(context, status),
                const SizedBox(height: 16),
                _releaseNotesPanel(context),
                if (_updateInfo.downloadUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _openRelease,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open release page'),
                    ),
                  ),
                ],
                if (_updateInfo.artifactUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _downloading ? null : _downloadArtifact,
                      icon: _downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(
                        _downloading
                            ? 'Downloading...'
                            : 'Download Windows ZIP',
                      ),
                    ),
                  ),
                ],
                if (_downloadedArtifact != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Downloaded to ${_downloadedArtifact!.path}',
                    style: const TextStyle(color: Colors.lightGreenAccent),
                  ),
                  if (Platform.isWindows) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _installing
                            ? null
                            : _installDownloadedArtifact,
                        icon: _installing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.restart_alt),
                        label: Text(
                          _installing
                              ? 'Preparing restart...'
                              : 'Install and Restart',
                        ),
                      ),
                    ),
                  ],
                ],
                if (Platform.isWindows &&
                    widget.rollbackDirectory != null &&
                    _rollbackAvailable) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _installing ? null : _rollbackInstalledUpdate,
                      icon: _installing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.undo),
                      label: Text(
                        _installing
                            ? 'Preparing rollback...'
                            : 'Rollback previous version',
                      ),
                    ),
                  ),
                ],
                if (_downloadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Download failed: $_downloadError',
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _updateStatusPanel(BuildContext context, UpdateStatusView status) {
    final color = switch (status.tone) {
      UpdateStatusTone.current => Colors.green.shade400,
      UpdateStatusTone.available => Theme.of(context).colorScheme.primary,
      UpdateStatusTone.error => Theme.of(context).colorScheme.error,
      UpdateStatusTone.muted => Theme.of(context).colorScheme.outline,
    };
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status.detail,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Latest version',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      status.latestVersionLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(width: 4, child: ColoredBox(color: color)),
          ),
        ],
      ),
    );
  }

  Widget _releaseNotesPanel(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(6),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Release Notes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_updateInfo.checkedAt case final checkedAt?)
                Text(
                  _checkedAtLabel(checkedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(
          height: 352,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: _updateInfo.releaseNotes.isEmpty
                ? Text(
                    'Release notes will appear here after checking for updates.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : SelectableText(_updateInfo.releaseNotes),
          ),
        ),
      ],
    ),
  );

  String _checkedAtLabel(String checkedAt) {
    final parsed = DateTime.tryParse(checkedAt)?.toLocal();
    if (parsed == null) return '';
    final date = MaterialLocalizations.of(context).formatShortDate(parsed);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(parsed));
    return 'Last checked $date, $time';
  }
}
