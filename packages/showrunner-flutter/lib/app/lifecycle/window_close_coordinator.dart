import 'dart:async';
import '../../features/settings/interface_preferences.dart';

enum WindowCloseChoice { hide, close, cancel }

/// Host boundary for close/tray decisions. Async runtime teardown is awaited
/// before handing the accepted close back to the native window.
final class WindowCloseCoordinator {
  WindowCloseCoordinator({
    required this.behavior,
    required this.ask,
    required this.hide,
    required this.confirmDocuments,
    required this.confirmProfile,
    required this.saveWindow,
    required this.shutdown,
    required this.closeWindow,
    this.shutdownTimeout = const Duration(seconds: 30),
  });
  final WindowCloseBehavior Function() behavior;
  final Future<WindowCloseChoice> Function() ask;
  final Future<bool> Function() hide;
  final Future<bool> Function() confirmDocuments;
  final Future<bool> Function() confirmProfile;
  final Future<void> Function() saveWindow;
  final Future<void> Function() shutdown;
  final Future<void> Function() closeWindow;
  final Duration shutdownTimeout;
  bool _inProgress = false;
  bool _closed = false;
  bool get isInProgress => _inProgress;

  Future<bool> request({bool forceClose = false}) async {
    if (_closed) return true;
    if (_inProgress) return false;
    _inProgress = true;
    try {
      if (!forceClose) {
        if (behavior() == WindowCloseBehavior.hideToTray && await hide()) {
          return false;
        }
        if (behavior() == WindowCloseBehavior.ask) {
          final choice = await ask();
          if (choice == WindowCloseChoice.cancel) return false;
          if (choice == WindowCloseChoice.hide && await hide()) return false;
        }
      }
      if (!await confirmDocuments() || !await confirmProfile()) return false;
      await saveWindow();
      await shutdown().timeout(
        shutdownTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Application shutdown is still running; the native window was not closed.',
            shutdownTimeout,
          );
        },
      );
      await closeWindow();
      _closed = true;
      return true;
    } finally {
      _inProgress = false;
    }
  }
}
