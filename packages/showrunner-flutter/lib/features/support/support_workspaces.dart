import 'dart:io';

import 'package:flutter/material.dart';

import '../../schema/update.dart';
import '../../services/structured_logger.dart';
import '../../services/update_check_service.dart';

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

class AboutWorkspace extends StatefulWidget {
  const AboutWorkspace({super.key, this.updateService});

  final UpdateCheckService? updateService;

  @override
  State<AboutWorkspace> createState() => _AboutWorkspaceState();
}

class _AboutWorkspaceState extends State<AboutWorkspace> {
  UpdateInfo _updateInfo = const UpdateInfo(
    currentVersion: showRunnerFlutterVersion,
    latestVersion: showRunnerFlutterVersion,
    hasUpdate: false,
  );
  bool _checking = false;

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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'About ShowRunner',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
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
    UpdateStatus.error => Text(
      _updateInfo.errorMessage ?? 'Unable to check for updates.',
      style: const TextStyle(color: Colors.orangeAccent),
    ),
    UpdateStatus.checking => const Text('Checking for updates...'),
    UpdateStatus.upToDate => const Text('ShowRunner is up to date.'),
    UpdateStatus.idle => const Text('Updates have not been checked yet.'),
  };
}
