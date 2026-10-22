import 'package:flutter/material.dart';
import 'shader_node_definitions.dart';

class ShaderNodePalette extends StatefulWidget {
  const ShaderNodePalette({super.key, required this.onAdd});
  final ValueChanged<ShaderNodeDefinition> onAdd;
  @override
  State<ShaderNodePalette> createState() => _ShaderNodePaletteState();
}

class _ShaderNodePaletteState extends State<ShaderNodePalette> {
  String search = '';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          decoration: const InputDecoration(labelText: 'Search shader nodes'),
          onChanged: (value) => setState(() => search = value),
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final category in shaderNodeCategories)
              ExpansionTile(
                initiallyExpanded: true,
                title: Text(category),
                children: [
                  for (final definition in shaderNodeDefinitions.where(
                    (item) =>
                        item.category == category &&
                        '${item.name} ${item.id}'.toLowerCase().contains(
                          search.toLowerCase(),
                        ),
                  ))
                    ListTile(
                      dense: true,
                      title: Text(definition.name),
                      onTap: () => widget.onAdd(definition),
                    ),
                ],
              ),
          ],
        ),
      ),
    ],
  );
}
