import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the Windows tray icon and keeps tray actions outside the page widget.
final class ShowRunnerTrayController with TrayListener {
  ShowRunnerTrayController({
    required this.onShowRequested,
    required this.onExitRequested,
  });

  final Future<void> Function() onShowRequested;
  final Future<void> Function() onExitRequested;
  bool _initialized = false;
  bool _hasIcon = false;
  bool _disposed = false;
  Future<void>? _starting;
  Future<void>? _stopping;

  Future<void> initialize() {
    if (_disposed) {
      return Future.error(StateError('Tray controller is closed.'));
    }
    return _starting ??= _initialize();
  }

  Future<void> _initialize() async {
    if (!Platform.isWindows || _initialized) return;
    await trayManager.setIcon('assets/app_icon.ico');
    _hasIcon = true;
    await trayManager.setToolTip('ShowRunner');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show ShowRunner'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Exit ShowRunner'),
        ],
      ),
    );
    if (!_disposed) trayManager.addListener(this);
    _initialized = true;
  }

  Future<void> dispose() {
    _disposed = true;
    return _stopping ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await _starting;
    } catch (_) {
      /* Initialization errors remain with the initialize caller. */
    }
    trayManager.removeListener(this);
    if (_hasIcon) await trayManager.destroy();
    _initialized = false;
    _hasIcon = false;
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(onShowRequested());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') unawaited(onShowRequested());
    if (menuItem.key == 'exit') unawaited(onExitRequested());
  }

  Future<void> hideWindow() async {
    await initialize();
    await windowManager.hide();
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }
}
