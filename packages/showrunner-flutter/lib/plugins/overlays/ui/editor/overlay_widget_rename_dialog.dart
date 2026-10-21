import 'package:flutter/material.dart';

class OverlayWidgetRenameDialog extends StatefulWidget {
  const OverlayWidgetRenameDialog({
    super.key,
    required this.widgetId,
    required this.name,
  });

  final String widgetId;
  final String name;

  @override
  State<OverlayWidgetRenameDialog> createState() =>
      _OverlayWidgetRenameDialogState();
}

class _OverlayWidgetRenameDialogState extends State<OverlayWidgetRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Rename ${widget.name}'),
    content: TextField(
      key: ValueKey('overlay-widget-rename-${widget.widgetId}'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Rename'),
      ),
    ],
  );
}
