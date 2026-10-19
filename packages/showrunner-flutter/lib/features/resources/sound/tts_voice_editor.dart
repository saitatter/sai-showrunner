part of '../resource_editor_registry.dart';

class _TtsVoiceEditor extends StatefulWidget {
  const _TtsVoiceEditor({required this.resource, required this.onSave});

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<_TtsVoiceEditor> createState() => _TtsVoiceEditorState();
}

class _TtsVoiceEditorState extends State<_TtsVoiceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _providerConfig;
  late final TextEditingController _pitch;
  late final TextEditingController _rate;
  late String _provider;

  @override
  void initState() {
    super.initState();
    final config = widget.resource.config;
    _name = TextEditingController(text: _displayValue(config['name']));
    _provider = _displayValue(config['voiceProvider']);
    _providerConfig = TextEditingController(
      text: _jsonDisplayValue(config['providerConfig']),
    );
    final providerConfig = config['providerConfig'] is Map
        ? Map<String, dynamic>.from(config['providerConfig'] as Map)
        : const <String, dynamic>{};
    _pitch = TextEditingController(
      text: _displayValue(providerConfig['pitch'] ?? 0),
    );
    _rate = TextEditingController(
      text: _displayValue(providerConfig['rate'] ?? 0),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _providerConfig.dispose();
    _pitch.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: 'Edit TTS voice',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TtsVoiceProviderPicker(
        value: _provider,
        onChanged: (value) => setState(() => _provider = value ?? ''),
      ),
      if (isSystemTtsProvider(_provider)) ...[
        TextField(
          controller: _pitch,
          inputFormatters: const [NumericInputFormatter()],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Pitch (-10 to 10)'),
        ),
        TextField(
          controller: _rate,
          inputFormatters: const [NumericInputFormatter()],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rate (-10 to 10)'),
        ),
      ] else
        TextField(
          controller: _providerConfig,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Provider config (JSON object)',
          ),
        ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'voiceProvider': _provider,
          'providerConfig': isSystemTtsProvider(_provider)
              ? {
                  'pitch': num.tryParse(_pitch.text.trim()) ?? 0,
                  'rate': num.tryParse(_rate.text.trim()) ?? 0,
                }
              : _parseJsonMap(_providerConfig.text),
        },
        state: widget.resource.state,
      ),
    ),
  );
}
