import 'dart:async';

import 'package:flutter/material.dart';

import '../resources/resource_options.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import '../../plugins/remote/satellite.dart';

class RemoteDashboardView extends StatelessWidget {
  const RemoteDashboardView({
    super.key,
    required this.connection,
    required this.dataService,
    required this.onDisconnect,
  });

  final RemoteSatelliteConnection connection;
  final ShowRunnerDataService dataService;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: connection,
    builder: (context, _) {
      final dashboard = connection.dashboard;
      if (dashboard == null) {
        return _RemoteConnectionProgress(
          connection: connection,
          onDisconnect: onDisconnect,
        );
      }
      return _RemoteDashboardContent(
        connection: connection,
        dataService: dataService,
        onDisconnect: onDisconnect,
        dashboard: dashboard,
      );
    },
  );
}

class _RemoteConnectionProgress extends StatelessWidget {
  const _RemoteConnectionProgress({
    required this.connection,
    required this.onDisconnect,
  });

  final RemoteSatelliteConnection connection;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connection.state == SatelliteConnectionState.connecting)
              const CircularProgressIndicator(),
            if (connection.state == SatelliteConnectionState.disconnected)
              const Icon(Icons.cloud_off, size: 42),
            const SizedBox(height: 16),
            Text(
              connection.state == SatelliteConnectionState.disconnected
                  ? 'Remote dashboard disconnected'
                  : 'Connecting to remote dashboard…',
            ),
            if (connection.lastError != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  '${connection.lastError}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onDisconnect,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to dashboards'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RemoteDashboardContent extends StatefulWidget {
  const _RemoteDashboardContent({
    required this.connection,
    required this.dataService,
    required this.onDisconnect,
    required this.dashboard,
  });

  final RemoteSatelliteConnection connection;
  final ShowRunnerDataService dataService;
  final VoidCallback onDisconnect;
  final RemoteDashboardConfig dashboard;

  @override
  State<_RemoteDashboardContent> createState() =>
      _RemoteDashboardContentState();
}

class _RemoteDashboardContentState extends State<_RemoteDashboardContent> {
  int _pageIndex = 0;
  bool _showSlots = false;

  @override
  Widget build(BuildContext context) {
    final pages = widget.dashboard.pages;
    final page = pages.isEmpty
        ? null
        : pages[_pageIndex.clamp(0, pages.length - 1)];
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  widget.connection.state == SatelliteConnectionState.connected
                      ? Icons.cloud_done
                      : Icons.cloud_queue,
                  color:
                      widget.connection.state ==
                          SatelliteConnectionState.connected
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.dashboard.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (pages.length > 1)
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _pageIndex == 0
                        ? null
                        : () => setState(() => _pageIndex--),
                    icon: const Icon(Icons.arrow_back),
                  ),
                if (page != null) Text('${_pageIndex + 1}/${pages.length}'),
                if (pages.length > 1)
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _pageIndex >= pages.length - 1
                        ? null
                        : () => setState(() => _pageIndex++),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.dashboard.resourceSlots.isEmpty
                      ? null
                      : () => setState(() => _showSlots = !_showSlots),
                  icon: const Icon(Icons.tune),
                  label: const Text('Slots'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: widget.onDisconnect,
                  icon: const Icon(Icons.close),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ),
        ),
        if (_showSlots)
          _RemoteSlotsPanel(
            connection: widget.connection,
            dataService: widget.dataService,
          ),
        Expanded(
          child: page == null
              ? const Center(child: Text('The remote dashboard has no pages.'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      page.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    for (final section in page.sections)
                      _RemoteDashboardSection(
                        connection: widget.connection,
                        page: page,
                        section: section,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RemoteDashboardSection extends StatelessWidget {
  const _RemoteDashboardSection({
    required this.connection,
    required this.page,
    required this.section,
  });

  final RemoteSatelliteConnection connection;
  final RemoteDashboardPage page;
  final RemoteDashboardSection section;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(section.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final widget in section.widgets)
                SizedBox(
                  width: widget.width * 100.0 + (widget.width - 1) * 4,
                  height: widget.height * 80.0 + (widget.height - 1) * 4,
                  child: _RemoteDashboardWidget(
                    connection: connection,
                    page: page,
                    section: section,
                    widget: widget,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RemoteDashboardWidget extends StatelessWidget {
  const _RemoteDashboardWidget({
    required this.connection,
    required this.page,
    required this.section,
    required this.widget,
  });

  final RemoteSatelliteConnection connection;
  final RemoteDashboardPage page;
  final RemoteDashboardSection section;
  final RemoteDashboardWidget widget;

  @override
  Widget build(BuildContext context) {
    if (widget.plugin == 'remote' && widget.widget == 'button') {
      return _RemoteButtonWidget(connection: connection, widget: widget);
    }
    if (widget.plugin == 'dashboards' && widget.widget == 'label') {
      return _RemoteLabelWidget(widget: widget);
    }
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Unsupported remote widget\n${widget.plugin}.${widget.widget}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _RemoteButtonWidget extends StatefulWidget {
  const _RemoteButtonWidget({required this.connection, required this.widget});

  final RemoteSatelliteConnection connection;
  final RemoteDashboardWidget widget;

  @override
  State<_RemoteButtonWidget> createState() => _RemoteButtonWidgetState();
}

class _RemoteButtonWidgetState extends State<_RemoteButtonWidget> {
  bool _busy = false;
  Object? _error;

  Future<void> _press() async {
    final triggerName =
        widget.widget.config['triggerName']?.toString().trim() ?? '';
    if (triggerName.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.connection.callWidgetRpc(widget.widget.id, 'pressbutton', [
        triggerName,
      ]);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(widget.widget.config['color'], Colors.red);
    final label = widget.widget.config['displayName']?.toString() ?? 'Button';
    return Tooltip(
      message: _error?.toString() ?? label,
      child: FilledButton(
        onPressed: _busy ? null : _press,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: color.computeLuminance() > .45
              ? Colors.black
              : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _RemoteLabelWidget extends StatelessWidget {
  const _RemoteLabelWidget({required this.widget});

  final RemoteDashboardWidget widget;

  @override
  Widget build(BuildContext context) {
    final color = _color(widget.config['color'], Colors.transparent);
    return Card(
      color: color,
      child: Center(
        child: Text(
          widget.config['label']?.toString() ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
    );
  }
}

class _RemoteSlotsPanel extends StatelessWidget {
  const _RemoteSlotsPanel({
    required this.connection,
    required this.dataService,
  });

  final RemoteSatelliteConnection connection;
  final ShowRunnerDataService dataService;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Remote resource slots',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose which local resource is exposed to the connected dashboard.',
          ),
          const SizedBox(height: 8),
          for (final slot in connection.slots)
            _RemoteSlotEditor(
              key: ValueKey(slot.id),
              connection: connection,
              dataService: dataService,
              slot: slot,
            ),
        ],
      ),
    ),
  );
}

class _RemoteSlotEditor extends StatefulWidget {
  const _RemoteSlotEditor({
    super.key,
    required this.connection,
    required this.dataService,
    required this.slot,
  });

  final RemoteSatelliteConnection connection;
  final ShowRunnerDataService dataService;
  final RemoteResourceSlot slot;

  @override
  State<_RemoteSlotEditor> createState() => _RemoteSlotEditorState();
}

class _RemoteSlotEditorState extends State<_RemoteSlotEditor> {
  late Future<List<ResourceData>> _resources;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resources = _loadResources();
  }

  Future<List<ResourceData>> _loadResources() async {
    final ids = await loadResourceOptions(
      widget.dataService,
      widget.slot.resourceType,
    );
    return [
      for (final id in ids)
        ResourceData(id: id, config: <String, dynamic>{'name': id}),
    ];
  }

  Future<void> _bind(String value) async {
    try {
      await widget.connection.bindSlot(
        widget.slot.id,
        value.isEmpty ? null : value,
      );
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ResourceData>>(
    future: _resources,
    builder: (context, snapshot) {
      final resources = snapshot.data ?? const <ResourceData>[];
      final selected =
          resources.any((resource) => resource.id == widget.slot.resourceId)
          ? widget.slot.resourceId
          : '';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text('${widget.slot.name} (${widget.slot.resourceType})'),
            ),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Local resource'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Unbound')),
                  for (final resource in resources)
                    DropdownMenuItem(
                      value: resource.id,
                      child: Text(resource.name),
                    ),
                ],
                onChanged: snapshot.connectionState == ConnectionState.waiting
                    ? null
                    : (value) => _bind(value ?? ''),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      );
    },
  );
}

Color _color(Object? value, Color fallback) {
  final text = value?.toString().trim() ?? '';
  final normalized = text.startsWith('#') ? text.substring(1) : text;
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? fallback : Color(parsed);
}
