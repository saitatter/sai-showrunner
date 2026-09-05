import 'dart:io';

import 'package:flutter/material.dart';

import '../../schema/update.dart';
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
        url: Uri.parse('https://www.github.com/LordTocs/ShowRunner'),
      ),
      _AboutLink(
        label: 'Help Discord',
        url: Uri.parse('https://discord.gg/txt4DUzYJM'),
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
  });

  final UpdateCheckService? updateService;
  final UpdateArtifactService? artifactService;
  final UpdateInstallService? installService;
  final Future<bool> Function()? onRestartRequested;
  final Directory? downloadDirectory;

  @override
  State<UpdateWorkspace> createState() => _UpdateWorkspaceState();
}

class _UpdateWorkspaceState extends State<UpdateWorkspace> {
  UpdateInfo _updateInfo = const UpdateInfo(
    currentVersion: showRunnerFlutterVersion,
    latestVersion: showRunnerFlutterVersion,
    hasUpdate: false,
  );
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  File? _downloadedArtifact;
  Object? _downloadError;

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final result =
        await (widget.updateService ??
                const UpdateCheckService(
                  currentVersion: showRunnerFlutterVersion,
                ))
            .check();
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
    } catch (error) {
      if (mounted) setState(() => _downloadError = error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _installDownloadedArtifact() async {
    final artifact = _downloadedArtifact;
    if (artifact == null || _installing || !Platform.isWindows) return;
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Updates', style: Theme.of(context).textTheme.headlineSmall),
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
                Text(
                  'Version Information',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.verified),
                  title: const Text('Current Version'),
                  subtitle: Text(_updateInfo.currentVersion),
                ),
                ListTile(
                  leading: const Icon(Icons.computer),
                  title: const Text('Platform Target'),
                  subtitle: Text(
                    '${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Dart Runtime Environment'),
                  subtitle: Text(Platform.version),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _checking ? null : _checkUpdate,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt),
                      label: Text(
                        _checking ? 'Checking...' : 'Check for Updates',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _updateStatus()),
                  ],
                ),
                if (_updateInfo.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Release notes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(_updateInfo.releaseNotes),
                ],
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

  Widget _updateStatus() => switch (_updateInfo.status) {
    UpdateStatus.available => Text(
      'Update available: ${_updateInfo.latestVersion}',
      style: const TextStyle(color: Colors.lightGreenAccent),
    ),
    UpdateStatus.downloaded => const Text(
      'Update downloaded and ready to install on restart.',
      style: TextStyle(color: Colors.lightGreenAccent),
    ),
    UpdateStatus.error => Text(
      _updateInfo.errorMessage ?? 'Unable to check for updates.',
      style: const TextStyle(color: Colors.orangeAccent),
    ),
    UpdateStatus.checking => const Text('Checking for updates...'),
    UpdateStatus.upToDate => const Text('ShowRunner is up to date.'),
    UpdateStatus.idle => const Text('Updates have not been checked yet.'),
  };
}
