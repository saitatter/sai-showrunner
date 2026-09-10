import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/tokens/colors.dart';
import '../ble/transport.dart';
import '../services/heart_rate_service.dart';

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
                subtitle: Text(service.device!.id),
                trailing: OutlinedButton(
                  onPressed: service.disconnect,
                  child: const Text('Disconnect'),
                ),
              ),
      ),
      const SizedBox(height: 12),
      _sectionCard(
        context,
        title: 'Live heart rate',
        icon: Icons.favorite_outline,
        child: Row(
          children: [
            const Icon(Icons.favorite, color: Color(0xfff43f5e), size: 34),
            const SizedBox(width: 12),
            Text(
              service.stale || service.bpm == null ? '--' : '${service.bpm}',
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
