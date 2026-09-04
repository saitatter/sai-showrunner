import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class InputPlatform {
  Stream<InputKeyEvent> get events;

  Future<void> simulateKeyDown(int virtualKeyCode);

  Future<void> simulateKeyUp(int virtualKeyCode);

  Future<void> simulateMouseDown(String button);

  Future<void> simulateMouseUp(String button);

  Future<void> startEvents();

  Future<void> stopEvents();

  Future<bool> isKeyDown(int virtualKeyCode);
}

final class InputKeyEvent {
  const InputKeyEvent({
    required this.virtualKeyCode,
    required this.pressed,
  });

  final int virtualKeyCode;
  final bool pressed;

  @override
  bool operator ==(Object other) =>
      other is InputKeyEvent &&
      other.virtualKeyCode == virtualKeyCode &&
      other.pressed == pressed;

  @override
  int get hashCode => Object.hash(virtualKeyCode, pressed);

  static InputKeyEvent? tryParse(Object? value) {
    if (value is! Map) return null;
    final rawVirtualKeyCode = value['vkCode'];
    final virtualKeyCode = rawVirtualKeyCode is num &&
        rawVirtualKeyCode == rawVirtualKeyCode.toInt() &&
        rawVirtualKeyCode >= 0 &&
        rawVirtualKeyCode <= 255
        ? rawVirtualKeyCode.toInt()
        : null;
    final type = value['type'];
    if (virtualKeyCode == null || type is! String) return null;
    if (type != 'key-pressed' && type != 'key-released') return null;
    return InputKeyEvent(
      virtualKeyCode: virtualKeyCode,
      pressed: type == 'key-pressed',
    );
  }
}

final class NativeInputPlatform implements InputPlatform {
  const NativeInputPlatform();

  static const _methods = MethodChannel('showrunner/input');
  static const _events = EventChannel('showrunner/input/events');
  static final _sharedEvents = _events
      .receiveBroadcastStream()
      .map(InputKeyEvent.tryParse)
      .where((event) => event != null)
      .cast<InputKeyEvent>();

  @override
  Stream<InputKeyEvent> get events {
    if (!Platform.isWindows) return const Stream<InputKeyEvent>.empty();
    return _sharedEvents;
  }

  @override
  Future<void> simulateKeyDown(int virtualKeyCode) => _invoke(
    'simulateKeyDown',
    {'vkCode': virtualKeyCode},
  );

  @override
  Future<void> simulateKeyUp(int virtualKeyCode) => _invoke(
    'simulateKeyUp',
    {'vkCode': virtualKeyCode},
  );

  @override
  Future<void> simulateMouseDown(String button) => _invoke(
    'simulateMouseDown',
    {'button': button},
  );

  @override
  Future<void> simulateMouseUp(String button) => _invoke(
    'simulateMouseUp',
    {'button': button},
  );

  @override
  Future<void> startEvents() => _invoke('startEvents', null);

  @override
  Future<void> stopEvents() => _invoke('stopEvents', null);

  @override
  Future<bool> isKeyDown(int virtualKeyCode) async {
    if (!Platform.isWindows) return false;
    final result = await _methods.invokeMethod<bool>(
      'isKeyDown',
      {'vkCode': virtualKeyCode},
    );
    return result ?? false;
  }

  Future<void> _invoke(String method, Object? arguments) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Native input is supported on Windows only.');
    }
    await _methods.invokeMethod<void>(method, arguments);
  }
}