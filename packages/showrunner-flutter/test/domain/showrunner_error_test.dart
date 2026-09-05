import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/domain/errors/showrunner_error.dart';
import 'package:showrunner_flutter/plugins/contracts/identifiers.dart';

void main() {
  test('serializes stable error metadata without losing the cause', () {
    final error = PluginConnectionError(
      pluginId: const PluginId('obs'),
      operationId: 'connect',
      technicalMessage: 'OBS socket refused the connection.',
      userMessage: 'OBS is unavailable. Check the connection settings.',
      cause: StateError('connection refused'),
    );

    expect(error.toString(), 'OBS socket refused the connection.');
    expect(error.retryable, isTrue);
    expect(error.toJson(), {
      'code': 'plugin.connection',
      'technicalMessage': 'OBS socket refused the connection.',
      'userMessage': 'OBS is unavailable. Check the connection settings.',
      'cause': 'Bad state: connection refused',
      'pluginId': 'obs',
      'operationId': 'connect',
      'retryable': true,
    });
  });

  test('keeps configuration and action failures distinguishable', () {
    const configuration = PluginConfigurationError(
      pluginId: PluginId('twitch'),
      operationId: 'chat',
      technicalMessage: 'Plugin is disabled: twitch',
      userMessage: 'Enable Twitch before running this action.',
    );
    const action = ActionExecutionError(
      pluginId: PluginId('twitch'),
      operationId: 'chat',
      technicalMessage: 'Unknown Dart action: twitch:chat',
      userMessage: 'This action is no longer available.',
    );

    expect(configuration.code, 'plugin.configuration');
    expect(action.code, 'action.execution');
  });
}
