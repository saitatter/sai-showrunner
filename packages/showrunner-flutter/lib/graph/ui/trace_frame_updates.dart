import 'package:flutter/scheduler.dart';

/// Flutter-only scheduling; runtime retention and projection stay UI independent.
void scheduleTraceFrame(void Function() update) {
  SchedulerBinding.instance.scheduleFrameCallback((_) => update());
  SchedulerBinding.instance.ensureVisualUpdate();
}
