import 'package:flutter/material.dart';

import '../../../schema/resource.dart';
import '../../../services/showrunner_data_service.dart';
import '../account_runtime.dart';

class BlueskyWorkspace extends StatefulWidget {
  const BlueskyWorkspace({super.key, required this.dataService});

  final ShowRunnerDataService dataService;

  @override
  State<BlueskyWorkspace> createState() => _BlueskyWorkspaceState();
}

class _BlueskyWorkspaceState extends State<BlueskyWorkspace> {
  late final BlueskyAccountAuthService _auth;
  late Future<List<ResourceData>> _accountsFuture;
  String? _busy;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _auth = BlueskyAccountAuthService(dataService: widget.dataService);
    _reload();
  }

  void _reload() {
    _accountsFuture = _auth.listAccounts();
    if (mounted) setState(() {});
  }

  Future<void> _addAccount() async {
    final draft = await showDialog<_AccountDraft>(
      context: context,
      builder: (context) => const _AccountDialog(),
    );
    if (draft == null || !mounted) return;
    await _signIn(
      accountId: 'account-${DateTime.now().microsecondsSinceEpoch}',
      draft: draft,
    );
  }

  Future<void> _signIn({
    required String accountId,
    required _AccountDraft draft,
  }) async {
    setState(() {
      _busy = accountId;
      _error = null;
    });
    try {
      await _auth.signIn(
        accountId: accountId,
        identifier: draft.identifier,
        appPassword: draft.password,
        name: draft.name,
      );
      _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _signInExisting(ResourceData account) async {
    final draft = await showDialog<_AccountDraft>(
      context: context,
      builder: (context) => _AccountDialog(
        initialName: account.config['name']?.toString(),
        initialIdentifier: account.config['identifier']?.toString(),
      ),
    );
    if (draft == null || !mounted) return;
    await _signIn(accountId: account.id, draft: draft);
  }

  Future<void> _delete(ResourceData account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bluesky account?'),
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
    if (confirmed != true) return;
    await _auth.deleteAccount(account.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ResourceData>>(
    future: _accountsFuture,
    builder: (context, snapshot) {
      final accounts = snapshot.data ?? const <ResourceData>[];
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Bluesky Accounts',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Sign in to the Bluesky accounts used by automations.'),
          const SizedBox(height: 20),
          if (_error != null) Text('Account sign-in error: $_error'),
          for (final account in accounts)
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.cloud_outlined,
                  color: account.config['session'] is Map
                      ? Colors.green
                      : Colors.amber,
                ),
                title: Text(account.name),
                subtitle: Text(
                  account.config['identifier']?.toString() ?? 'Not connected',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    OutlinedButton(
                      onPressed: _busy == null
                          ? () => _signInExisting(account)
                          : null,
                      child: Text(
                        _busy == account.id ? 'Signing in...' : 'Sign in again',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete account',
                      onPressed: _busy == null ? () => _delete(account) : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          if (accounts.isEmpty)
            const ListTile(title: Text('No Bluesky accounts defined.')),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy == null ? _addAccount : null,
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
          ),
        ],
      );
    },
  );
}

final class _AccountDraft {
  const _AccountDraft({
    required this.name,
    required this.identifier,
    required this.password,
  });

  final String name;
  final String identifier;
  final String password;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.initialName, this.initialIdentifier});

  final String? initialName;
  final String? initialIdentifier;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _name;
  late final TextEditingController _identifier;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _identifier = TextEditingController(text: widget.initialIdentifier ?? '');
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in to Bluesky'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Account name'),
          ),
          TextField(
            controller: _identifier,
            decoration: const InputDecoration(labelText: 'Handle or DID'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'App password'),
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
          _AccountDraft(
            name: _name.text,
            identifier: _identifier.text,
            password: _password.text,
          ),
        ),
        child: const Text('Sign in'),
      ),
    ],
  );
}
