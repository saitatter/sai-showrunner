import '../../schema/automation.dart';

/// ShowRunner-owned metadata that travels alongside a `sai_nodes` payload.
///
/// The graph package owns clipboard transport and node IDs. ShowRunner keeps
/// only the domain metadata that cannot be reconstructed from a generic node:
/// plugin configuration, variable/trigger markers, and custom titles.
final class ShowRunnerClipboardSnapshot {
  const ShowRunnerClipboardSnapshot({
    required this.nodeType,
    required this.data,
    this.title,
    this.isVariable = false,
    this.isTrigger = false,
  });

  final String nodeType;
  final JsonMap data;
  final String? title;
  final bool isVariable;
  final bool isTrigger;
}

/// Bounded host-payload storage for the generic `sai_nodes` clipboard.
///
/// The system clipboard contains the package payload. This store is an
/// in-process fallback for payloads copied by the current editor and is
/// deliberately bounded so a long-running desktop session cannot retain an
/// unbounded history of graph metadata.
final class ShowRunnerClipboardPayloadStore {
  ShowRunnerClipboardPayloadStore({this.maxEntries = 8})
    : assert(maxEntries > 0);

  final int maxEntries;
  final Map<String, List<ShowRunnerClipboardSnapshot>> _metadata = {};
  String? inMemoryPayload;

  List<ShowRunnerClipboardSnapshot>? snapshotsFor(String payload) {
    final snapshots = _metadata[payload];
    return snapshots == null ? null : List.unmodifiable(snapshots);
  }

  void remember(
    String payload,
    Iterable<ShowRunnerClipboardSnapshot> snapshots,
  ) {
    if (payload.isEmpty) return;
    final value = List<ShowRunnerClipboardSnapshot>.unmodifiable(snapshots);
    if (value.isEmpty) return;
    _metadata[payload] = value;
    while (_metadata.length > maxEntries) {
      _metadata.remove(_metadata.keys.first);
    }
  }

  void clear() {
    inMemoryPayload = null;
    _metadata.clear();
  }
}
