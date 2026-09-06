import 'package:sai_nodes/sai_nodes.dart';

/// Classifies the mutation events emitted by `sai_nodes`.
///
/// The hosted package does not expose a public content-revision notifier yet,
/// so this compatibility boundary keeps ShowRunner's dirty-state policy in a
/// single adapter. Selection, hover, pan, zoom, focus, and temporary wires do
/// not count as persisted content mutations.
abstract final class SaiNodesContentRevision {
  static bool isContentMutation(NodeEditorEvent event) =>
      event is AddLinkEvent ||
      event is RemoveLinkEvent ||
      event is NodeResizeEvent ||
      event is NodeRenameEvent ||
      event is LinkLabelChangeEvent ||
      event is DragSelectionEvent ||
      event is AddNodeEvent ||
      event is RemoveNodeEvent ||
      event is PasteSelectionEvent ||
      event is CutSelectionEvent ||
      event is NodeLayoutEvent ||
      (event is NodeFieldEvent && event.eventType != FieldEventType.change);
}
