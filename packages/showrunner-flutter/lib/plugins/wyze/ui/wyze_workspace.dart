import 'package:flutter/material.dart';

import '../../../schema/resource.dart';
import '../../../services/showrunner_data_service.dart';
import '../account_runtime.dart';

class WyzeWorkspace extends StatefulWidget {
  const WyzeWorkspace({super.key, required this.dataService});

  final ShowRunnerDataService dataService;

  @override
  State<WyzeWorkspace> createState() => _WyzeWorkspaceState();
}

class _WyzeWorkspaceState extends State<WyzeWorkspace> {
  late final WyzeAccountAuthService _auth;
  late Future<ResourceData?> _accountFuture;
  String? _busy;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _auth = WyzeAccountAuthService(dataService: widget.dataService);
    _reload();
  }

  void _reload() {
    _accountFuture = _auth.loadAccount();
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    final account = await _accountFuture;
    if (!mounted) return;
    final draft = await showDialog<_WyzeDraft>(
      context: context,
      builder: (context) => _WyzeDialog(
        initialName: account?.config['name']?.toString(),
        initialEmail: account?.config['email']?.toString(),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _busy = 'main';
      _error = null;
    });
    try {
      await _auth.signIn(
        email: draft.email,
        password: draft.password,
        name: draft.name,
      );
      _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete(ResourceData account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Wyze account?'),
        content: Text('Delete ${account.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = 'main';
      _error = null;
    });
    try {
      await _auth.deleteAccount();
      _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ResourceData?>(
    future: _accountFuture,
    builder: (context, snapshot) {
      final account = snapshot.data;
      final authenticated = account?.state['authenticated'] == true;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Wyze Account',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Connect the Wyze account used by device automations.'),
          const SizedBox(height: 20),
          if (_error != null) Text('Account sign-in error: $_error'),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.videocam_outlined,
                color: authenticated ? Colors.green : Colors.amber,
              ),
              title: Text(account?.name ?? 'No Wyze account defined'),
              subtitle: Text(
                account?.config['email']?.toString() ?? 'Not connected',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  OutlinedButton(
                    onPressed: _busy == null ? _signIn : null,
                    child: Text(
                      _busy == 'main'
                          ? 'Signing in...'
                          : authenticated
                          ? 'Sign in again'
                          : 'Sign in',
                    ),
                  ),
                  if (account != null)
                    IconButton(
                      tooltip: 'Delete account',
                      onPressed: _busy == null ? () => _delete(account) : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

final class _WyzeDraft {
  const _WyzeDraft({
    required this.name,
    required this.email,
    required this.password,
  });

  final String name;
  final String email;
  final String password;
}

class _WyzeDialog extends StatefulWidget {
  const _WyzeDialog({this.initialName, this.initialEmail});

  final String? initialName;
  final String? initialEmail;

  @override
  State<_WyzeDialog> createState() => _WyzeDialogState();
}

class _WyzeDialogState extends State<_WyzeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _email = TextEditingController(text: widget.initialEmail ?? '');
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in to Wyze'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Account name'),
          ),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _WyzeDraft(
            name: _name.text,
            email: _email.text,
            password: _password.text,
          ),
        ),
        child: const Text('Sign in'),
      ),
    ],
  );
}
