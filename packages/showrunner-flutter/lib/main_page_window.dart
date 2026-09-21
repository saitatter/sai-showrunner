part of 'main.dart';

extension _ShowRunnerPageWindow on _ShowRunnerPageState {
  Future<void> _showWindow() async {
    final tray = _tray;
    if (tray != null) {
      await tray.showWindow();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  Future<bool> _hideToTray() async {
    try {
      final tray = _tray;
      if (tray == null) return false;
      await tray.hideWindow();
      return true;
    } catch (error, stackTrace) {
      stderr.writeln('ShowRunner could not hide to tray: $error');
      stderr.writeln(stackTrace);
      return false;
    }
  }

  Future<_WindowCloseChoice> _askWindowCloseChoice() async {
    return await showDialog<_WindowCloseChoice>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Close ShowRunner?'),
            content: const Text(
              'Would you like to keep ShowRunner running in the system tray or close it completely?',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_WindowCloseChoice.cancel),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(_WindowCloseChoice.hide),
                child: const Text('Hide to tray'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_WindowCloseChoice.close),
                child: const Text('Close'),
              ),
            ],
          ),
        ) ??
        _WindowCloseChoice.cancel;
  }

  Future<bool> _handleWindowClose({bool forceClose = false}) async {
    if (!mounted || _isWindowCloseInProgress) return false;
    _isWindowCloseInProgress = true;
    try {
      if (!forceClose) {
        final behavior = _interfacePreferences.windowCloseBehavior;
        if (behavior == WindowCloseBehavior.hideToTray) {
          if (await _hideToTray()) return false;
        } else if (behavior == WindowCloseBehavior.ask) {
          final choice = await _askWindowCloseChoice();
          if (choice == _WindowCloseChoice.cancel) return false;
          if (choice == _WindowCloseChoice.hide) {
            if (await _hideToTray()) return false;
          }
        }
      }
      if (!await _confirmAllAutomationClose()) return false;
      if (!await _profileWorkspaceController.confirmClose()) return false;
      await saveShowRunnerWindowState(_windowStateFile);
      await windowManager.setPreventClose(false);
      // Re-issue the close through the normal Win32 path after releasing the
      // interception. This lets the runner finish its native shutdown flow.
      await windowManager.close();
      return true;
    } finally {
      _isWindowCloseInProgress = false;
    }
  }

  Future<bool> _handleUpdateRestart() => _handleWindowClose();
}
