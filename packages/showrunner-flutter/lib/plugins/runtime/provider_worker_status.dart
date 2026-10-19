enum ProviderWorkerState { stopped, starting, running, reconnecting, error }

extension ProviderWorkerStatePresentation on ProviderWorkerState {
  String get label => switch (this) {
    ProviderWorkerState.stopped => 'Stopped',
    ProviderWorkerState.starting => 'Starting',
    ProviderWorkerState.running => 'Running',
    ProviderWorkerState.reconnecting => 'Reconnecting',
    ProviderWorkerState.error => 'Error',
  };
}
