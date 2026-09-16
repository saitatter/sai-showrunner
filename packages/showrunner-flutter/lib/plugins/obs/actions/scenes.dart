part of '../actions.dart';

List<ActionSpec<dynamic, dynamic>> _obsSceneActions(
  ObsTransport transport,
  List<String> previousScenes,
) => [
  ActionSpec<ObsSceneConfig, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('scene'),
    displayName: 'Change Scene',
    configSchema: const DartDataInputSchema(
      label: 'Scene configuration',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Scene',
          key: 'scene',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ],
    ),
    configCodec: obsSceneConfigCodec,
    invoke: (config, context) async {
      final scene = config.scene;
      if (scene == null || scene.isEmpty) return null;
      final current = await transport.call('GetCurrentProgramScene', {});
      final currentScene = current['currentProgramSceneName']?.toString();
      if (currentScene != null &&
          currentScene.isNotEmpty &&
          currentScene != scene) {
        previousScenes.add(currentScene);
      }
      await transport.call('SetCurrentProgramScene', {'sceneName': scene});
      return null;
    },
  ),
  ActionSpec<ObsEmptyConfig, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('prevScene'),
    displayName: 'Previous Scene',
    configSchema: _emptyConfigSchema,
    configCodec: obsEmptyConfigCodec,
    invoke: (config, context) async {
      if (previousScenes.isEmpty) return null;
      final scene = previousScenes.removeLast();
      await transport.call('SetCurrentProgramScene', {'sceneName': scene});
      return {'scene': scene};
    },
  ),
];
