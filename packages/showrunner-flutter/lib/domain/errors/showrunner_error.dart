import '../../plugins/contracts/identifiers.dart';

/// A stable error contract shared by the application, runtime and plugins.
///
/// The underlying cause remains available for diagnostics, while callers can
/// use [userMessage] without parsing provider-specific exception strings.
sealed class ShowRunnerError implements Exception {
  const ShowRunnerError({
    required this.code,
    required this.technicalMessage,
    required this.userMessage,
    this.cause,
    this.stackTrace,
    this.pluginId,
    this.operationId,
    this.retryable = false,
  });

  final String code;
  final String technicalMessage;
  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;
  final PluginId? pluginId;
  final String? operationId;
  final bool retryable;

  Map<String, dynamic> toJson() => {
    'code': code,
    'technicalMessage': technicalMessage,
    'userMessage': userMessage,
    if (cause != null) 'cause': cause.toString(),
    if (pluginId != null) 'pluginId': pluginId!.value,
    if (operationId != null) 'operationId': operationId,
    'retryable': retryable,
  };

  @override
  String toString() => technicalMessage;
}

final class PluginConnectionError extends ShowRunnerError {
  const PluginConnectionError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = true,
  }) : super(code: 'plugin.connection');
}

final class PluginAuthenticationError extends ShowRunnerError {
  const PluginAuthenticationError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = false,
  }) : super(code: 'plugin.authentication');
}

final class PluginConfigurationError extends ShowRunnerError {
  const PluginConfigurationError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = false,
  }) : super(code: 'plugin.configuration');
}

final class ActionExecutionError extends ShowRunnerError {
  const ActionExecutionError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = false,
  }) : super(code: 'action.execution');
}

final class TriggerSubscriptionError extends ShowRunnerError {
  const TriggerSubscriptionError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = true,
  }) : super(code: 'trigger.subscription');
}

final class ResourceNotFoundError extends ShowRunnerError {
  const ResourceNotFoundError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = false,
  }) : super(code: 'resource.not_found');
}

final class ValidationError extends ShowRunnerError {
  const ValidationError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = false,
  }) : super(code: 'validation');
}

final class PersistenceError extends ShowRunnerError {
  const PersistenceError({
    required super.technicalMessage,
    required super.userMessage,
    super.cause,
    super.stackTrace,
    super.pluginId,
    super.operationId,
    super.retryable = true,
  }) : super(code: 'persistence');
}
