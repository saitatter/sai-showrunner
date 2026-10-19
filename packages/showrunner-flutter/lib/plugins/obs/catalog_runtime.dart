import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import 'transport.dart';

typedef ObsCatalogCall =
    Future<RuntimeMap> Function(String request, RuntimeMap data);

final class ObsSceneItem {
  const ObsSceneItem({
    required this.id,
    required this.sourceName,
    required this.enabled,
    required this.transform,
  });

  final int id;
  final String sourceName;
  final bool enabled;
  final RuntimeMap transform;
}

final class ObsSourceFilter {
  const ObsSourceFilter({required this.name, required this.enabled});

  final String name;
  final bool enabled;
}

final class ObsSceneCatalog {
  const ObsSceneCatalog({
    required this.scenes,
    required this.itemsByScene,
    required this.inputKindsByName,
    required this.filtersBySource,
    this.currentProgramScene,
  });

  final List<String> scenes;
  final Map<String, List<ObsSceneItem>> itemsByScene;
  final Map<String, String> inputKindsByName;
  final Map<String, List<ObsSourceFilter>> filtersBySource;
  final String? currentProgramScene;
}

final class ObsCatalogService {
  ObsCatalogService({required this.dataService, this.call});

  final ShowRunnerDataService dataService;
  final ObsCatalogCall? call;

  Future<ObsSceneCatalog> load() async {
    final ownedTransport = call == null ? await _transportFromSettings() : null;
    final fetch = call ?? ownedTransport!.call;
    try {
      final scenesResponse = await fetch('GetSceneList', {});
      final rawScenes = scenesResponse['scenes'];
      final scenes = rawScenes is List
          ? rawScenes
                .whereType<Map>()
                .map((scene) => scene['sceneName']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toList()
          : <String>[];
      final itemResponses = await Future.wait(
        scenes.map((scene) => fetch('GetSceneItemList', {'sceneName': scene})),
      );
      final inputResponse = await fetch('GetInputList', {});
      final inputKindsByName = _inputKinds(inputResponse);
      final sourceNames = {
        for (final items in [
          for (final response in itemResponses) _items(response),
        ])
          for (final item in items) item.sourceName,
      };
      final filterResponses = await Future.wait(
        sourceNames.map(
          (source) => fetch('GetSourceFilterList', {'sourceName': source}),
        ),
      );
      return ObsSceneCatalog(
        scenes: scenes,
        currentProgramScene: scenesResponse['currentProgramSceneName']
            ?.toString(),
        itemsByScene: {
          for (var index = 0; index < scenes.length; index++)
            scenes[index]: _items(itemResponses[index]),
        },
        inputKindsByName: inputKindsByName,
        filtersBySource: {
          for (var index = 0; index < sourceNames.length; index++)
            sourceNames.elementAt(index): _filters(filterResponses[index]),
        },
      );
    } finally {
      await ownedTransport?.close();
    }
  }

  Future<ObsWebSocketTransport> _transportFromSettings() async {
    final settings = await dataService.loadPluginSettings('obs');
    final host = settings['host']?.toString().trim().isNotEmpty == true
        ? settings['host'].toString().trim()
        : '127.0.0.1';
    final port = settings['port'] is num
        ? (settings['port'] as num).toInt()
        : int.tryParse('${settings['port']}') ?? 4455;
    final password = settings['password']?.toString();
    return ObsWebSocketTransport(
      host: host,
      port: port,
      password: password?.isEmpty == true ? null : password,
    );
  }
}

Map<String, String> _inputKinds(RuntimeMap response) {
  final rawInputs = response['inputs'];
  if (rawInputs is! List) return const {};
  return {
    for (final raw in rawInputs.whereType<Map>())
      if (raw['inputName']?.toString().isNotEmpty == true)
        raw['inputName'].toString(): raw['inputKind']?.toString() ?? '',
  };
}

List<ObsSourceFilter> _filters(RuntimeMap response) {
  final rawFilters = response['filters'];
  if (rawFilters is! List) return const [];
  return rawFilters
      .whereType<Map>()
      .map(
        (raw) => ObsSourceFilter(
          name: raw['filterName']?.toString() ?? '',
          enabled: raw['filterEnabled'] != false,
        ),
      )
      .where((filter) => filter.name.isNotEmpty)
      .toList();
}

List<ObsSceneItem> _items(RuntimeMap response) {
  final rawItems = response['sceneItems'];
  if (rawItems is! List) return const [];
  return rawItems
      .whereType<Map>()
      .map((raw) {
        final id = raw['sceneItemId'];
        final transform = raw['sceneItemTransform'];
        return ObsSceneItem(
          id: id is num ? id.toInt() : int.tryParse('$id') ?? -1,
          sourceName: raw['sourceName']?.toString() ?? 'Unknown source',
          enabled: raw['sceneItemEnabled'] != false,
          transform: transform is Map
              ? Map<String, dynamic>.from(transform)
              : const {},
        );
      })
      .where((item) => item.id >= 0)
      .toList();
}
