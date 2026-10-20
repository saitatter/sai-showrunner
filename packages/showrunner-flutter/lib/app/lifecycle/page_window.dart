part of '../showrunner_page.dart';

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

  Future<WindowCloseChoice> _askWindowCloseChoice() async {
    return await showDialog<WindowCloseChoice>(
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
                    Navigator.of(context).pop(WindowCloseChoice.cancel),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(WindowCloseChoice.hide),
                child: const Text('Hide to tray'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(WindowCloseChoice.close),
                child: const Text('Close'),
              ),
            ],
          ),
        ) ??
        WindowCloseChoice.cancel;
  }

  Future<bool> _handleWindowClose({bool forceClose = false}) async {
    if (!mounted || _disposed) return false;
    try {
      return await _windowClose.request(forceClose: forceClose);
    } catch (error, stack) {
      ShowRunnerLogger.instance.error(
        'lifecycle',
        'Window close failed',
        error: error,
        stackTrace: stack,
      );
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Unable to close ShowRunner: $error',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
      return false;
    }
  }

  Future<bool> _handleUpdateRestart() => _handleWindowClose();
}
