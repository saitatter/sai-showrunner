part of '../resource_editor_registry.dart';

class _ConnectionEditor extends StatefulWidget {
  const _ConnectionEditor({
    required this.title,
    required this.resource,
    required this.onSave,
    this.supportsLocal = false,
    this.testConnection,
  });

  final String title;
  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;
  final bool supportsLocal;
  final Future<bool> Function(String host, int port, String? password)?
  testConnection;

  @override
  State<_ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends State<_ConnectionEditor> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _password;
  late final TextEditingController _installPath;
  late bool _local;
  bool _testing = false;
  bool? _testSuccess;
  Object? _testError;

  @override
  void initState() {
    super.initState();
    final config = widget.resource.config;
    _name = TextEditingController(text: _displayValue(config['name']));
    _host = TextEditingController(text: _displayValue(config['host']));
    _port = TextEditingController(text: _displayValue(config['port']));
    _password = TextEditingController(text: _displayValue(config['password']));
    _installPath = TextEditingController(
      text: _displayValue(config['installPath']),
    );
    _local = config['local'] == true;
  }

  @override
  void dispose() {
    for (final controller in [_name, _host, _port, _password, _installPath]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _test() async {
    final tester = widget.testConnection;
    if (tester == null) return;
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null || port < 0 || port > 65535) {
      setState(() {
        _testSuccess = false;
        _testError = const FormatException('Enter a valid host and port.');
      });
      return;
    }
    setState(() {
      _testing = true;
      _testSuccess = null;
      _testError = null;
    });
    try {
      final success = await tester(host, port, _password.text);
      if (!mounted) return;
      setState(() => _testSuccess = success);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testError = error;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: widget.title,
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _host,
        decoration: const InputDecoration(labelText: 'Host'),
      ),
      TextField(
        controller: _port,
        inputFormatters: const [
          NumericInputFormatter(decimal: false, signed: false),
        ],
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Port'),
      ),
      if (widget.testConnection != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'WebSocket Password',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _testSuccess == true
                          ? Icons.check
                          : _testSuccess == false
                          ? Icons.close
                          : Icons.wifi_find,
                    ),
              label: const Text('Test'),
            ),
          ],
        )
      else
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
      if (_testError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Connection test failed: $_testError',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        )
      else if (_testSuccess == true)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('OBS responded successfully.'),
        ),
      if (widget.supportsLocal) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Local OBS installation'),
          value: _local,
          onChanged: (value) => setState(() => _local = value),
        ),
        if (_local)
          TextField(
            controller: _installPath,
            decoration: const InputDecoration(labelText: 'Install path'),
          ),
      ],
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'host': _host.text.trim(),
          'port': int.tryParse(_port.text.trim()) ?? 4455,
          'password': _password.text,
          if (widget.supportsLocal) 'local': _local,
          if (widget.supportsLocal) 'installPath': _installPath.text.trim(),
        },
        state: widget.resource.state,
      ),
    ),
  );
}

Future<bool> _testObsConnection(String host, int port, String? password) async {
  final transport = ObsWebSocketTransport(
    host: host,
    port: port,
    password: password?.isEmpty == true ? null : password,
  );
  try {
    await transport.call('GetVersion', {});
    return true;
  } finally {
    await transport.close();
  }
}
