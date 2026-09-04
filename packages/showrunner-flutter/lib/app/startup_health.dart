import '../services/showrunner_data_service.dart';

enum StartupHealthState { loading, ready, offline, error }

final class StartupHealthSnapshot {
  const StartupHealthSnapshot({required this.state, this.health, this.error});

  final StartupHealthState state;
  final ShowRunnerHealth? health;
  final Object? error;
}

final class StartupHealthLoader {
  const StartupHealthLoader(this.dataService);

  final ShowRunnerDataService dataService;

  Future<StartupHealthSnapshot> load() async {
    try {
      final health = await dataService.health();
      return StartupHealthSnapshot(
        state: health.isReady
            ? StartupHealthState.ready
            : StartupHealthState.offline,
        health: health,
      );
    } catch (error) {
      return StartupHealthSnapshot(
        state: StartupHealthState.error,
        error: error,
      );
    }
  }
}
