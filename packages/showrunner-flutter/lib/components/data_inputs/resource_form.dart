import 'package:flutter/material.dart';
import '../../persistence/filesystem/file_transaction.dart';
import '../../persistence/secret_storage_exception.dart';

/// A save owns its draft until accepted; failures keep the dialog open.
class ResourceForm extends StatefulWidget {
  const ResourceForm({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    this.validate,
  });
  final String title;
  final List<Widget> fields;
  final Future<void> Function() onSave;
  final bool Function()? validate;
  @override
  State<ResourceForm> createState() => _ResourceFormState();
}

class _ResourceFormState extends State<ResourceForm> {
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (_saving || widget.validate?.call() == false) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error) {
            PersistenceConflictException() =>
              'This resource changed elsewhere. Close and reopen it before saving.',
            SecretStorageException() =>
              'Encrypted credentials are unavailable. Restore access before saving.',
            _ =>
              'The resource could not be saved. Your edits remain open; restore storage access and retry.',
          };
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...widget.fields,
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}
