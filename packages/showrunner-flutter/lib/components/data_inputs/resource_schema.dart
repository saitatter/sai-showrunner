import '../../schema/data_input.dart';

typedef ResourceOptionsLoader =
    Future<List<String>> Function(String resourceType);

/// Resolves product resources without mutating a plugin's declarative schema.
Future<DartDataInputSchema> hydrateResourceSchema(
  DartDataInputSchema schema,
  ResourceOptionsLoader loader,
) async {
  final fields = await Future.wait(
    schema.fields.map((field) => hydrateResourceSchema(field, loader)),
  );
  final item = schema.itemSchema == null
      ? null
      : await hydrateResourceSchema(schema.itemSchema!, loader);
  final options =
      schema.kind == DartDataInputKind.resource &&
          schema.options.isEmpty &&
          schema.resourceType != null
      ? await loader(schema.resourceType!.value)
      : schema.options;
  return DartDataInputSchema(
    label: schema.label,
    kind: schema.kind,
    key: schema.key,
    options: options,
    required: schema.required,
    secret: schema.secret,
    multiline: schema.multiline,
    template: schema.template,
    defaultValue: schema.defaultValue,
    resourceType: schema.resourceType,
    fields: fields,
    itemKind: schema.itemKind,
    itemSchema: item,
    editor: schema.editor,
    allowMargin: schema.allowMargin,
    allowPadding: schema.allowPadding,
    allowHorizontalAlign: schema.allowHorizontalAlign,
    allowVerticalAlign: schema.allowVerticalAlign,
    graphEditor: schema.graphEditor,
  );
}
