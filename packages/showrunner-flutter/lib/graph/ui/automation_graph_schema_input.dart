import 'package:flutter/material.dart';
import '../../components/data_inputs/data_input.dart';
import '../../components/data_inputs/resource_schema.dart';

class AutomationGraphSchemaInput extends StatefulWidget {
  const AutomationGraphSchemaInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
    this.loader,
  });
  final DartDataInputSchema schema;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final ResourceOptionsLoader? loader;
  @override
  State<AutomationGraphSchemaInput> createState() =>
      _AutomationGraphSchemaInputState();
}

class _AutomationGraphSchemaInputState
    extends State<AutomationGraphSchemaInput> {
  late Future<DartDataInputSchema> schema = _load();
  Future<DartDataInputSchema> _load() => widget.loader == null
      ? Future.value(widget.schema)
      : hydrateResourceSchema(widget.schema, widget.loader!);
  @override
  void didUpdateWidget(AutomationGraphSchemaInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema != widget.schema ||
        oldWidget.loader != widget.loader) {
      schema = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DartDataInputSchema>(
    future: schema,
    builder: (context, snapshot) =>
        snapshot.connectionState == ConnectionState.waiting
        ? const LinearProgressIndicator()
        : snapshot.hasError
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unable to load ${widget.schema.label}. Check the resource connection and retry.',
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  schema = _load();
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          )
        : snapshot.hasData
        ? DartDataInput(
            schema: snapshot.data!,
            value: widget.value,
            onChanged: widget.onChanged,
          )
        : const LinearProgressIndicator(),
  );
}
