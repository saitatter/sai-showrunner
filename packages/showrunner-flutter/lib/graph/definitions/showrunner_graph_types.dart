import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../../schema/data_input.dart';

String graphTypeForInput(DartDataInputKind kind) => switch (kind) {
  DartDataInputKind.text ||
  DartDataInputKind.multilineText ||
  DartDataInputKind.enumeration => 'core.string',
  DartDataInputKind.number => 'core.number',
  DartDataInputKind.boolean => 'core.boolean',
  DartDataInputKind.array => 'core.array',
  DartDataInputKind.object => 'core.object',
  DartDataInputKind.color => 'showrunner.color',
  DartDataInputKind.duration => 'showrunner.duration',
  DartDataInputKind.filePath => 'showrunner.file',
  DartDataInputKind.resource => 'showrunner.resource',
  DartDataInputKind.keyboardKey => 'showrunner.keyboardKey',
  DartDataInputKind.keyCombo => 'showrunner.keyCombo',
  DartDataInputKind.obsTransform => 'showrunner.obsTransform',
  DartDataInputKind.lightColor => 'showrunner.lightColor',
};
GraphTypeSystem createShowrunnerGraphTypes() {
  final types = GraphTypeSystem.core();
  for (final id in {
    'color',
    'duration',
    'file',
    'resource',
    'keyboardKey',
    'keyCombo',
    'obsTransform',
    'lightColor',
  }) {
    types.register(GraphDataType(id: 'showrunner.$id', label: id));
  }
  return types;
}

String actionNodeType(String plugin, String action) =>
    'action:${Uri.encodeComponent(plugin)}/${Uri.encodeComponent(action)}';
String triggerNodeType(String plugin, String trigger) =>
    'trigger:${Uri.encodeComponent(plugin)}/${Uri.encodeComponent(trigger)}';
(String, String)? decodeContractNodeType(String type, String prefix) {
  if (!type.startsWith('$prefix:')) return null;
  final parts = type.substring(prefix.length + 1).split('/');
  if (parts.length != 2) return null;
  try {
    return (Uri.decodeComponent(parts[0]), Uri.decodeComponent(parts[1]));
  } on FormatException {
    return null;
  }
}

String automationNodeKind(String type) {
  if (decodeContractNodeType(type, 'action') != null) return 'action';
  if (decodeContractNodeType(type, 'trigger') != null) return 'trigger';
  if (type.startsWith('showrunner.')) {
    return type.substring('showrunner.'.length);
  }
  return 'unresolved';
}
