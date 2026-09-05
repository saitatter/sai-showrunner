import '../../schema/automation.dart';

enum AutomationDocumentKind { v2, legacy, unsupported }

final class AutomationDocumentDetection {
  const AutomationDocumentDetection({required this.kind, this.reason});

  final AutomationDocumentKind kind;
  final String? reason;

  bool get needsMigration => kind == AutomationDocumentKind.legacy;
}

/// Classifies persisted automation data without attempting to repair it.
///
/// The V2 decoder remains strict. This classifier only decides whether the
/// compatibility boundary should be offered for a non-V2 document.
final class LegacyAutomationDetector {
  const LegacyAutomationDetector();

  AutomationDocumentDetection detect(JsonMap source) {
    final schemaVersion = source['schemaVersion'];
    final graph = source['graph'];
    if (schemaVersion == 2 && _isGraph(graph)) {
      return const AutomationDocumentDetection(kind: AutomationDocumentKind.v2);
    }

    final hasLegacySequence =
        source['sequence'] is Map ||
        source['sequence'] is List ||
        source['floatingSequences'] is List ||
        source['actions'] is List;
    final hasGraphShape = graph is Map;
    if (schemaVersion != 2 && (hasLegacySequence || hasGraphShape)) {
      return const AutomationDocumentDetection(
        kind: AutomationDocumentKind.legacy,
      );
    }

    return AutomationDocumentDetection(
      kind: AutomationDocumentKind.unsupported,
      reason: schemaVersion == 2
          ? 'V2 automation is missing graph.nodes.'
          : 'Document does not contain a recognized automation shape.',
    );
  }
}

bool _isGraph(Object? value) =>
    value is Map && (value['nodes'] is List) && (value['edges'] is List);
