part of '../resource_editor_registry.dart';

class _OverlayWidgetConfigEditor extends StatelessWidget {
  const _OverlayWidgetConfigEditor({
    required this.plugin,
    required this.widget,
    required this.config,
    required this.onChanged,
    required this.catalog,
    required this.templateSuggestions,
  });

  final String plugin;
  final String widget;
  final JsonMap config;
  final ValueChanged<JsonMap> onChanged;
  final List<GeneratedOverlayWidget> catalog;
  final List<String> templateSuggestions;

  @override
  Widget build(BuildContext context) {
    GeneratedOverlayWidget? definition;
    for (final candidate in catalog) {
      if (candidate.pluginId == plugin && candidate.id == widget) {
        definition = candidate;
        break;
      }
    }
    if (definition == null) {
      return TextFormField(
        initialValue: const JsonEncoder.withIndent('  ').convert(config),
        minLines: 4,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: 'Widget config (JSON object)',
          alignLabelWithHint: true,
        ),
        onChanged: (value) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map) onChanged(Map<String, dynamic>.from(decoded));
          } on FormatException {
            // Preserve the last valid config while the JSON is edited.
          }
        },
      );
    }
    final configSchema = definition.configSchema;
    final normalizedConfig = mergeOverlayWidgetDefaults(configSchema, config);
    final textAlignmentSchema = configSchema.fields
        .where((field) => field.editor == 'overlayTextAlignment')
        .firstOrNull;
    final blockStyleSchema = configSchema.fields
        .where((field) => field.editor == 'overlayBlockStyle')
        .firstOrNull;
    final hasVerticalOnlyAlignment =
        textAlignmentSchema != null &&
        blockStyleSchema != null &&
        blockStyleSchema.allowMargin == false &&
        blockStyleSchema.allowPadding == false &&
        blockStyleSchema.allowHorizontalAlign == false &&
        blockStyleSchema.allowVerticalAlign != false;
    if (hasVerticalOnlyAlignment) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in configSchema.fields)
            if (field == textAlignmentSchema)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OverlayLabelAlignmentInput(
                  showLabels: false,
                  textAlignmentSchema: textAlignmentSchema,
                  textAlignment: normalizedConfig['textAlign'],
                  onTextAlignmentChanged: (next) =>
                      onChanged({...normalizedConfig, 'textAlign': next}),
                  blockStyleSchema: blockStyleSchema,
                  blockStyle: normalizedConfig['block'],
                  onBlockStyleChanged: (next) =>
                      onChanged({...normalizedConfig, 'block': next}),
                ),
              )
            else if (field != blockStyleSchema)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DartDataInput(
                  key: ValueKey(field.key ?? field.label),
                  schema: field,
                  value: normalizedConfig[field.key ?? field.label],
                  templateSuggestions: {
                    ...templateSuggestions,
                    ..._overlayTemplateSuggestions(catalog),
                  }.toList()..sort(),
                  onChanged: (value) {
                    onChanged({
                      ...normalizedConfig,
                      field.key ?? field.label: value,
                    });
                  },
                ),
              ),
        ],
      );
    }
    return DartDataInput(
      key: ValueKey('$plugin.$widget'),
      schema: configSchema,
      value: normalizedConfig,
      templateSuggestions: {
        ...templateSuggestions,
        ..._overlayTemplateSuggestions(catalog),
      }.toList()..sort(),
      onChanged: (value) {
        if (value is Map) onChanged(Map<String, dynamic>.from(value));
      },
    );
  }
}

List<String> _overlayTemplateSuggestions(List<GeneratedOverlayWidget> catalog) {
  final suggestions = <String>{
    'viewerName',
    'displayName',
    'username',
    'user',
    'message',
    'text',
    'amount',
    'currency',
    'platform',
    'event',
  };
  for (final definition in catalog) {
    final states = definition.capabilities['states'];
    if (states is List) {
      for (final state in states) {
        suggestions.add('${definition.pluginId}.${state.toString()}');
      }
    }
  }
  return suggestions.toList()..sort();
}
