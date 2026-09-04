import 'package:flutter/material.dart';

final class TtsVoiceProviderOption {
  const TtsVoiceProviderOption({required this.id, required this.label});

  final String id;
  final String label;
}

const ttsVoiceProviderOptions = <TtsVoiceProviderOption>[
  TtsVoiceProviderOption(id: 'system', label: 'System voice'),
  TtsVoiceProviderOption(id: 'azure', label: 'Azure'),
  TtsVoiceProviderOption(id: 'google', label: 'Google'),
  TtsVoiceProviderOption(id: 'elevenlabs', label: 'ElevenLabs'),
];

bool isSystemTtsProvider(String? provider) =>
    provider?.isNotEmpty == true && provider!.startsWith('system');

String ttsVoiceProviderLabel(String provider) {
  for (final option in ttsVoiceProviderOptions) {
    if (option.id == provider) return option.label;
  }
  if (isSystemTtsProvider(provider)) return 'System voice: $provider';
  return 'Configured provider: $provider';
}

final class TtsVoiceProviderPicker extends StatelessWidget {
  const TtsVoiceProviderPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value?.trim() ?? '';
    final items = [
      ...ttsVoiceProviderOptions,
      if (current.isNotEmpty &&
          !ttsVoiceProviderOptions.any((option) => option.id == current))
        TtsVoiceProviderOption(
          id: current,
          label: ttsVoiceProviderLabel(current),
        ),
    ];
    return DropdownButtonFormField<String>(
      initialValue: current.isEmpty ? null : current,
      decoration: const InputDecoration(labelText: 'Voice provider'),
      items: [
        for (final option in items)
          DropdownMenuItem(value: option.id, child: Text(option.label)),
      ],
      onChanged: onChanged,
    );
  }
}