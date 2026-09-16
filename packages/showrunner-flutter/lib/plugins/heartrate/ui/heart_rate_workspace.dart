import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/tokens/colors.dart';
import '../ble/transport.dart';
import '../services/heart_rate_service.dart';
import '../services/heart_rate_zones.dart';

class HeartRateWorkspace extends StatefulWidget {
  const HeartRateWorkspace({super.key, required this.service});

  final HeartRateService service;

  @override
  State<HeartRateWorkspace> createState() => _HeartRateWorkspaceState();
}

class _HeartRateWorkspaceState extends State<HeartRateWorkspace> {
  List<BleScanResult> _scanResults = const [];
  bool _scanning = false;
  Object? _error;
  final _history = <int>[];

  HeartRateService get service => widget.service;

  @override
  void initState() {
    super.initState();
    service.addListener(_onChanged);
  }

  @override
  void dispose() {
    service.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Row(
        children: [
          const Icon(Icons.favorite, color: Color(0xfff43f5e), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Heart Rate',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text('Bluetooth heart-rate monitoring for ShowRunner.'),
              ],
            ),
          ),
          _StatusBadge(status: service.status),
        ],
      ),
      const SizedBox(height: 20),
      if (_error != null) _ErrorCard(error: _error!),
      _sectionCard(
        context,
        title: 'Bluetooth',
        icon: Icons.bluetooth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service.status == HeartRateConnectionStatus.unavailable
                  ? 'Bluetooth adapter is unavailable.'
                  : service.simulation
                  ? 'Simulation backend ready.'
                  : 'Native Bluetooth backend ready.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: Icon(_scanning ? Icons.hourglass_top : Icons.search),
                  label: Text(_scanning ? 'Scanning…' : 'Scan for devices'),
                ),
                OutlinedButton.icon(
                  onPressed: _scanning ? service.cancelScan : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop scan'),
                ),
              ],
            ),
            if (_scanResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final device in _scanResults) _scanRow(context, device),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      _sectionCard(
        context,
        title: 'Connected device',
        icon: Icons.monitor_heart_outlined,
        child: service.device == null
            ? const Text('No device connected.')
            : ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.device!.name),
                subtitle: Text(
                  '${service.device!.id}\n'
                  'RSSI ${service.device!.rssi ?? '—'} dBm'
                  '${service.batteryPercent == null ? '' : ' · Battery ${service.batteryPercent}%'}',
                ),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: service.disconnect,
                      child: const Text('Disconnect'),
                    ),
                    OutlinedButton(
                      onPressed: () => unawaited(_forgetDevice()),
                      child: const Text('Forget'),
                    ),
                  ],
                ),
              ),
      ),
      const SizedBox(height: 12),
      _sectionCard(
        context,
        title: 'Live heart rate',
        icon: Icons.favorite_outline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, color: Color(0xfff43f5e), size: 34),
                const SizedBox(width: 12),
                Text(
                  service.stale || service.bpm == null
                      ? '--'
                      : '${service.bpm}',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(width: 8),
                const Text('BPM'),
                const Spacer(),
                _Stat(
                  label: 'Min',
                  value: service.stats.minBpm?.toString() ?? '--',
                ),
                _Stat(
                  label: 'Avg',
                  value: service.stats.averageBpm?.toStringAsFixed(0) ?? '--',
                ),
                _Stat(
                  label: 'Max',
                  value: service.stats.maxBpm?.toString() ?? '--',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  service.zoneState['zone']?.toString() ?? 'No zone',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: service.stats.sampleCount == 0
                      ? null
                      : service.resetStatistics,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset statistics'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _sectionCard(
        context,
        title: 'Heart-rate history',
        icon: Icons.show_chart,
        child: SizedBox(
          height: 140,
          width: double.infinity,
          child: _history.isEmpty
              ? const Center(child: Text('Waiting for heart-rate data.'))
              : CustomPaint(
                  painter: _HeartRateChartPainter(
                    values: List<int>.from(_history),
                    stale: service.stale,
                  ),
                ),
        ),
      ),
      const SizedBox(height: 12),
      _sectionCard(
        context,
        title: 'Zones',
        icon: Icons.layers_outlined,
        child: _ZonesEditor(service: service),
      ),
      if (service.transport is FakeBleTransportLike) ...[
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Simulation',
          icon: Icons.science_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: service.simulation
                    ? null
                    : () => unawaited(_startSimulation()),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start H808S simulation'),
              ),
              OutlinedButton.icon(
                onPressed: service.simulation
                    ? () => unawaited(service.stopSimulation())
                    : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop simulation'),
              ),
              if (service.simulation) const Chip(label: Text('SIMULATED')),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      _sectionCard(
        context,
        title: 'Diagnostics',
        icon: Icons.bug_report_outlined,
        child: Text(
          'Packets: ${service.packetCount} · Malformed: ${service.malformedPacketCount}\n'
          'Backend: ${service.transport.runtimeType}\n'
          '${service.lastError ?? 'No errors reported.'}',
        ),
      ),
    ],
  );

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _scanResults = const [];
    });
    try {
      _scanResults = await service.scan();
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _startSimulation() async {
    try {
      await service.startSimulation();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Widget _scanRow(BuildContext context, BleScanResult device) => Card(
    child: ListTile(
      leading: const Icon(Icons.favorite, color: Color(0xfff43f5e)),
      title: Text(device.name),
      subtitle: Text('Heart Rate Service · RSSI ${device.rssi ?? '—'} dBm'),
      trailing: FilledButton(
        onPressed: () => unawaited(_connect(device)),
        child: const Text('Connect'),
      ),
    ),
  );

  Future<void> _connect(BleScanResult device) async {
    try {
      await service.connect(device.id, deviceName: device.name);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _forgetDevice() async {
    try {
      await service.forgetPreferredDevice();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) => Card(
    color: ShowRunnerColors.surfaceA,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xfff43f5e)),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

  void _onChanged() {
    final bpm = service.bpm;
    if (bpm != null) {
      _history.add(bpm);
      if (_history.length > 60) _history.removeAt(0);
    }
    if (mounted) setState(() {});
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final HeartRateConnectionStatus status;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      status == HeartRateConnectionStatus.streaming
          ? Icons.check_circle
          : Icons.circle,
      size: 16,
    ),
    label: Text(status.name),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [Text(label), Text(value)],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: const Text('Heart Rate error'),
      subtitle: Text('$error'),
    ),
  );
}

class _HeartRateChartPainter extends CustomPainter {
  const _HeartRateChartPainter({required this.values, required this.stale});

  final List<int> values;
  final bool stale;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ShowRunnerColors.surfaceD
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = stale ? ShowRunnerColors.textSecondary : const Color(0xfff43f5e)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (var row = 1; row < 4; row++) {
      final y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length < 2) return;
    final max = values.reduce((a, b) => a > b ? a : b).clamp(1, 240);
    final min = values.reduce((a, b) => a < b ? a : b).clamp(0, max - 1);
    final range = (max - min).toDouble();
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = (values[index] - min) / range;
      final y = size.height * (1 - normalized.clamp(0, 1));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_HeartRateChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.stale != stale;
}

class _ZonesEditor extends StatefulWidget {
  const _ZonesEditor({required this.service});

  final HeartRateService service;

  @override
  State<_ZonesEditor> createState() => _ZonesEditorState();
}

class _ZonesEditorState extends State<_ZonesEditor> {
  late List<_ZoneDraft> _drafts;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _drafts = _draftsFrom(widget.service.zones);
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < _drafts.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _drafts[index].name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _drafts[index].min,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _drafts[index].max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _drafts[index].color,
                  decoration: const InputDecoration(labelText: 'Color'),
                ),
              ),
              IconButton(
                tooltip: 'Delete zone',
                onPressed: _drafts.length <= 1
                    ? null
                    : () => setState(() {
                        _drafts.removeAt(index).dispose();
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      if (_error != null)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 4),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _drafts.add(
                _ZoneDraft(
                  HeartRateZoneConfig(
                    id: 'zone-${_drafts.length + 1}',
                    name: 'Zone ${_drafts.length + 1}',
                    minBpm: (_drafts.last._maxValue ?? 0) + 1,
                    color: '#9146ff',
                  ),
                ),
              );
            }),
            icon: const Icon(Icons.add),
            label: const Text('Add zone'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(() {
              for (final draft in _drafts) {
                draft.dispose();
              }
              _drafts = _draftsFrom(defaultHeartRateZones);
              _error = null;
            }),
            child: const Text('Reset defaults'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => unawaited(_save()),
            child: const Text('Save zones'),
          ),
        ],
      ),
    ],
  );

  Future<void> _save() async {
    try {
      final zones = [
        for (var index = 0; index < _drafts.length; index++)
          _drafts[index].toConfig(index),
      ];
      await widget.service.saveZones(zones);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  List<_ZoneDraft> _draftsFrom(List<HeartRateZoneConfig> zones) => [
    for (final zone in zones) _ZoneDraft(zone),
  ];
}

class _ZoneDraft {
  _ZoneDraft(HeartRateZoneConfig zone)
    : id = zone.id,
      name = TextEditingController(text: zone.name),
      min = TextEditingController(text: '${zone.minBpm}'),
      max = TextEditingController(text: zone.maxBpm?.toString() ?? ''),
      color = TextEditingController(text: zone.color);

  final String id;
  final TextEditingController name;
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController color;

  int? get _maxValue => int.tryParse(max.text.trim());

  HeartRateZoneConfig toConfig(int index) => HeartRateZoneConfig(
    id: id.isEmpty ? 'zone-${index + 1}' : id,
    name: name.text.trim(),
    minBpm: int.parse(min.text.trim()),
    maxBpm: _maxValue,
    color: color.text.trim(),
  );

  void dispose() {
    name.dispose();
    min.dispose();
    max.dispose();
    color.dispose();
  }
}
