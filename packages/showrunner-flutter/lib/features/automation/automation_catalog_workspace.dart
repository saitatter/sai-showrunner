import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../persistence/automation_repository.dart';
import '../../runtime/automation_recovery.dart';
import '../../schema/automation.dart';
import '../../services/showrunner_data_service.dart';

class AutomationCatalogWorkspace extends StatefulWidget {
  const AutomationCatalogWorkspace({
    super.key,
    required this.dataService,
    this.entriesLoader,
    this.onOpen,
    this.onRepair,
    this.onCreate,
    this.onDelete,
  });

  final ShowRunnerDataService dataService;
  final Future<List<AutomationCatalogEntry>> Function()? entriesLoader;
  final FutureOr<void> Function(AutomationData automation, String fileName)?
  onOpen;
  final Future<void> Function(AutomationData automation, String fileName)?
  onRepair;
  final Future<void> Function()? onCreate;
  final Future<void> Function(String fileName)? onDelete;

  @override
  State<AutomationCatalogWorkspace> createState() =>
      _AutomationCatalogWorkspaceState();
}

class _AutomationCatalogWorkspaceState
    extends State<AutomationCatalogWorkspace> {
  late Future<List<AutomationCatalogEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  Future<List<AutomationCatalogEntry>> _loadEntries() =>
      widget.entriesLoader?.call() ??
      AutomationRepository.loadDirectory(
        Directory('${widget.dataService.userDirectory.path}/automations'),
      );

  void _refresh() {
    setState(() {
      _entriesFuture = _loadEntries();
    });
  }

  Future<void> _create() async {
    if (widget.onCreate == null) return;
    await widget.onCreate!();
    if (mounted) _refresh();
  }

  Future<void> _delete(String fileName) async {
    if (widget.onDelete == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete automation?'),
        content: Text('Delete $fileName permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onDelete!(fileName);
    if (mounted) _refresh();
  }

  Future<void> _repair(AutomationData automation, String fileName) async {
    if (widget.onRepair == null) return;
    await widget.onRepair!(automation, fileName);
    if (mounted) _refresh();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<AutomationCatalogEntry>>(
    future: _entriesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Text('Automations unavailable: ${snapshot.error}'),
        );
      }
      final entries = snapshot.data ?? const <AutomationCatalogEntry>[];
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Text(
                'Automations',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.onCreate == null ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('Create automation'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${entries.length} saved automation${entries.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const ListTile(
              leading: Icon(Icons.inbox),
              title: Text('No saved automations'),
            )
          else
            ...entries.map((entry) {
              final automation = entry.automation;
              final issues = automation == null
                  ? const <String>[]
                  : validateAutomationGraph(automation);
              return ListTile(
                leading: Icon(
                  entry.isValid && issues.isEmpty
                      ? Icons.account_tree
                      : Icons.error_outline,
                ),
                title: Text(
                  automation?.extra['name']?.toString() ?? entry.fileName,
                ),
                subtitle: Text(
                  entry.isValid
                      ? issues.isEmpty
                            ? '${automation!.graph.nodes.length} nodes, ${automation.graph.edges.length} links'
                            : 'Needs repair: ${issues.first}'
                      : 'Invalid automation: ${entry.error}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.isValid && issues.isEmpty)
                      IconButton(
                        tooltip: 'Open in graph editor',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => unawaited(
                          Future<void>.sync(
                            () => widget.onOpen?.call(
                              automation!,
                              entry.fileName,
                            ),
                          ),
                        ),
                      )
                    else if (entry.isValid && automation != null)
                      IconButton(
                        tooltip: 'Repair automation graph',
                        icon: const Icon(Icons.build_circle_outlined),
                        onPressed: () => _repair(automation, entry.fileName),
                      ),
                    IconButton(
                      tooltip: 'Delete automation',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: widget.onDelete == null
                          ? null
                          : () => _delete(entry.fileName),
                    ),
                  ],
                ),
                onTap: entry.isValid && issues.isEmpty
                    ? () => unawaited(
                        Future<void>.sync(
                          () =>
                              widget.onOpen?.call(automation!, entry.fileName),
                        ),
                      )
                    : null,
              );
            }),
        ],
      );
    },
  );
}
