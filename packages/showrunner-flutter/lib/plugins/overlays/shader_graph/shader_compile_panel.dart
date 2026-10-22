import 'package:flutter/material.dart';
import 'shader_graph_compiler.dart';

class ShaderCompilePanel extends StatelessWidget {
  const ShaderCompilePanel({
    super.key,
    required this.result,
    required this.showGlsl,
    this.onApply,
  });
  final ShaderGraphCompileResult result;
  final bool showGlsl;
  final VoidCallback? onApply;
  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.all(12),
    children: [
      for (final error in result.errors)
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      for (final warning in result.warnings) Text(warning),
      if (result.isValid) const Text('Shader compiled successfully.'),
      if (showGlsl) SelectableText(result.glsl),
      if (onApply != null)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: onApply, child: const Text('Apply')),
        ),
    ],
  );
}
