import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/tts_voice_editor.dart';
import 'editor/audio_splitter_editor.dart';
import 'package:showrunner_flutter/features/resources/connection/map_resource_contribution.dart';

List<ResourceEditorContribution> createSoundResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('TTSVoice'),
    builder: (context, resource, onSave) =>
        TtsVoiceEditor(resource: resource, onSave: onSave),
  ),
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('AudioSplitterOutput'),
    builder: (context, resource, onSave) =>
        AudioSplitterEditor(resource: resource, onSave: onSave),
  ),
  mapResourceContribution(
    builtInResourceSpec('SoundOutput'),
    fields: const [
      'name',
      'type',
      'deviceId',
      'webId',
      'isDefault',
      'overlayId',
    ],
  ),
  mapResourceContribution(
    builtInResourceSpec('TTSVoiceProvider'),
    fields: const ['name', 'provider', 'providerId', 'config'],
  ),
];
