import 'dart:async';
import '../../features/chat/command_manager.dart';
import '../../features/chat/command_plugin.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';

void registerConfiguredChatCommands(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
  required Future<ChatCommandManager>? chatCommands,
}) {
  registry.register(
    createChatCommandsPlugin(
      manager: () =>
          chatCommands ??
          Future.error(StateError('Chat Commands runtime is unavailable.')),
      eventHub: eventHub,
    ),
  );
}

void registerDefaultChatCommands(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  registry.register(
    createChatCommandsPlugin(
      manager: () =>
          Future.error(StateError('Chat Commands runtime is unavailable.')),
      eventHub: eventHub,
    ),
  );
}
