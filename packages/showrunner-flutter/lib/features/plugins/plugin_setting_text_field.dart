import 'package:flutter/material.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../components/data_inputs/numeric_input_formatter.dart';

class PluginSettingTextField extends StatelessWidget {
  const PluginSettingTextField({
    super.key,
    required this.definition,
    required this.controller,
    this.showId = false,
    this.enabled = true,
  });
  final DartSettingContract definition;
  final TextEditingController controller;
  final bool showId, enabled;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      enabled: enabled,
      obscureText: definition.secret,
      keyboardType: definition.valueType == DartSettingType.number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      inputFormatters: definition.valueType == DartSettingType.number
          ? const [NumericInputFormatter()]
          : null,
      decoration: InputDecoration(
        labelText: definition.displayName,
        helperText: showId ? definition.id.value : null,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
