import 'dart:ui';

class OverlaySnapResult {
  const OverlaySnapResult(this.bounds, this.vertical, this.horizontal);
  final Rect bounds;
  final List<double> vertical;
  final List<double> horizontal;
}

OverlaySnapResult snapOverlayBounds({
  required Rect bounds,
  required Size stage,
  required List<Rect> peers,
  required double tolerance,
  bool resize = false,
  bool left = false,
  bool right = false,
  bool top = false,
  bool bottom = false,
}) {
  final xs = <double>{
    for (final peer in peers) ...[peer.left, peer.center.dx, peer.right],
    0,
    stage.width / 2,
    stage.width,
  };
  final ys = <double>{
    for (final peer in peers) ...[peer.top, peer.center.dy, peer.bottom],
    0,
    stage.height / 2,
    stage.height,
  };
  (double, double?) axis(
    double start,
    double end,
    double limit,
    Set<double> targets,
    bool moveStart,
    bool moveEnd,
  ) {
    var best = tolerance + .000001;
    var correction = 0.0;
    double? guide;
    final anchors = resize
        ? [if (moveStart) start, if (moveEnd) end]
        : [start, (start + end) / 2, end];
    for (final anchor in anchors) {
      for (final target in targets) {
        final distance = (target - anchor).abs();
        final delta = resize
            ? target.roundToDouble() - anchor
            : (start + target - anchor).roundToDouble() - start;
        final nextStart = start + (resize ? (moveStart ? delta : 0) : delta);
        final nextEnd = end + (resize ? (moveEnd ? delta : 0) : delta);
        if (distance < best &&
            nextStart >= 0 &&
            nextEnd <= limit &&
            (!resize || nextEnd - nextStart >= 24)) {
          best = distance;
          correction = delta;
          guide = target;
        }
      }
    }
    return (correction, guide);
  }

  final x = axis(bounds.left, bounds.right, stage.width, xs, left, right);
  final y = axis(bounds.top, bounds.bottom, stage.height, ys, top, bottom);
  return OverlaySnapResult(
    resize
        ? Rect.fromLTRB(
            bounds.left + (left ? x.$1 : 0),
            bounds.top + (top ? y.$1 : 0),
            bounds.right + (right ? x.$1 : 0),
            bounds.bottom + (bottom ? y.$1 : 0),
          )
        : bounds.shift(Offset(x.$1, y.$1)),
    [if (x.$2 != null) x.$2!],
    [if (y.$2 != null) y.$2!],
  );
}
