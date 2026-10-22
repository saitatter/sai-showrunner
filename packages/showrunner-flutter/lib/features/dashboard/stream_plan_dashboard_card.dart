import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/brand_icons.dart';
import '../../design_system/tokens/tokens.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/stream_plans/manifest.dart';
import '../../schema/resource.dart';
import '../../schema/stream_plan.dart';

import 'dashboard_widgets.dart';

class StreamPlanDashboardCard extends StatefulWidget {
  const StreamPlanDashboardCard({
    super.key,
    required this.plans,
    required this.runtime,
    required this.registryFuture,
  });

  final List<ResourceData> plans;
  final DartStreamPlanRuntime? runtime;
  final Future<DartPluginRegistry> registryFuture;

  @override
  State<StreamPlanDashboardCard> createState() =>
      _StreamPlanDashboardCardState();
}

class _StreamPlanDashboardCardState extends State<StreamPlanDashboardCard> {
  String? _selectedPlanId;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedPlanId = widget.plans.firstOrNull?.id;
    widget.runtime?.addListener(_runtimeChanged);
  }

  ResourceData? get _selectedPlan {
    final id = _selectedPlanId;
    if (id == null) return null;
    return widget.plans.where((plan) => plan.id == id).firstOrNull;
  }

  @override
  void didUpdateWidget(covariant StreamPlanDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      oldWidget.runtime?.removeListener(_runtimeChanged);
      widget.runtime?.addListener(_runtimeChanged);
    }
    final active = widget.runtime?.activePlanId;
    if (active != null && widget.plans.any((plan) => plan.id == active)) {
      _selectedPlanId = active;
    } else if (!widget.plans.any((plan) => plan.id == _selectedPlanId)) {
      _selectedPlanId = widget.plans.firstOrNull?.id;
    }
  }

  void _runtimeChanged() {
    if (!mounted) return;
    final active = widget.runtime?.activePlanId;
    if (active != null && widget.plans.any((plan) => plan.id == active)) {
      _selectedPlanId = active;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.runtime?.removeListener(_runtimeChanged);
    super.dispose();
  }

  Future<void> _toggle() async {
    final runtime = widget.runtime;
    final plan = _selectedPlan;
    if (runtime == null || plan == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registry = await widget.registryFuture;
      if (runtime.activePlanId == plan.id) {
        await runtime.deactivatePlan(registry: registry);
      } else {
        await runtime.activatePlan(
          plan.id,
          StreamPlanData.fromConfig(plan.config),
          registry: registry,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(bool forward) async {
    final runtime = widget.runtime;
    final plan = _selectedPlan;
    if (runtime == null || plan == null || runtime.activePlanId != plan.id) {
      return;
    }
    try {
      final registry = await widget.registryFuture;
      if (forward) {
        await runtime.transitionToNextSegment(
          plan.id,
          StreamPlanData.fromConfig(plan.config),
          registry: registry,
        );
      } else {
        await runtime.transitionToPreviousSegment(
          plan.id,
          StreamPlanData.fromConfig(plan.config),
          registry: registry,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final selected = _selectedPlan;
    final active = selected != null && runtime?.activePlanId == selected.id;
    StreamPlanData? parsed;
    Object? loadError;
    if (selected != null) {
      try {
        parsed = StreamPlanData.fromConfig(selected.config);
      } catch (error) {
        loadError = error;
      }
    }
    return DashboardCard(
      icon: mdiIcon(0xF00F0),
      title: 'Stream Plan',
      child: SizedBox(
        height: 292,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selected?.id,
                    hint: const Text('Select a plan'),
                    items: [
                      for (final plan in widget.plans)
                        DropdownMenuItem(
                          value: plan.id,
                          child: Text(plan.name),
                        ),
                    ],
                    onChanged: widget.plans.isEmpty || active
                        ? null
                        : (value) => setState(() => _selectedPlanId = value),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: active
                      ? 'Deactivate stream plan'
                      : 'Activate stream plan',
                  onPressed:
                      _busy || selected == null || (!active && parsed == null)
                      ? null
                      : _toggle,
                  icon: Icon(active ? Icons.stop_circle : Icons.play_circle),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: ShowRunnerColors.surfaceBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(4),
                child: selected == null
                    ? const SizedBox.expand()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final segment
                                in parsed?.segments ??
                                    <StreamPlanSegmentData>[])
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Chip(label: Text(segment.name)),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
            if (selected != null && parsed != null) ...[
              const SizedBox(height: 4),
              Text(
                active
                    ? 'Active${runtime?.activeSegmentId == null ? '' : ' · ${runtime!.activeSegmentId}'}'
                    : '${parsed.segments.length} segments',
              ),
              if (active)
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous segment',
                      onPressed: () => _move(false),
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      tooltip: 'Next segment',
                      onPressed: () => _move(true),
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
            ],
            if (loadError != null)
              Text(
                'Invalid stream plan: $loadError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_error != null)
              Text(
                'Stream Plan action failed: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
