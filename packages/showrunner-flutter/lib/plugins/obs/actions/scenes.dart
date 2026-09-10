part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _obsSceneActions(
  ObsTransport transport,
  List<String> previousScenes,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
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
    invoke: (config, context) async {
      final scene = config['scene']?.toString();
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
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('prevScene'),
    displayName: 'Previous Scene',
    configSchema: _emptyConfigSchema,
    invoke: (config, context) async {
      if (previousScenes.isEmpty) return null;
      final scene = previousScenes.removeLast();
      await transport.call('SetCurrentProgramScene', {'sceneName': scene});
      return {'scene': scene};
    },
  ),
];
