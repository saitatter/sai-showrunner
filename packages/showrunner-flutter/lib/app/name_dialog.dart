import 'package:flutter/material.dart';

Future<String?> showShowRunnerNameDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  String label = 'Name',
  String confirmLabel = 'Create',
}) => showDialog<String>(
  context: context,
  builder: (context) => _ShowRunnerNameDialog(
    title: title,
    initialName: initialName,
    label: label,
    confirmLabel: confirmLabel,
  ),
);

class _ShowRunnerNameDialog extends StatefulWidget {
  const _ShowRunnerNameDialog({
    required this.title,
    required this.initialName,
    required this.label,
    required this.confirmLabel,
  });

  final String title;
  final String initialName;
  final String label;
  final String confirmLabel;

  @override
  State<_ShowRunnerNameDialog> createState() => _ShowRunnerNameDialogState();
}

class _ShowRunnerNameDialogState extends State<_ShowRunnerNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty ? null : _submit,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
