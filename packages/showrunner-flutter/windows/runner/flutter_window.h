#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/event_channel.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  bool StartInputEvents(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
  void StopInputEvents();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetupInputChannels();
  void HandleInputMethod(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool EnsureInputWindow();
  bool SendKeyInput(int virtual_key_code, bool pressed);
  bool SendMouseInput(const std::string& button, bool pressed);
  void HandleInputMessage(LPARAM lparam);
  void HandleInputKey(unsigned int virtual_key_code, bool pressed);
  static LRESULT CALLBACK InputWindowProc(HWND window, UINT message,
                                          WPARAM wparam, LPARAM lparam);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      input_method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      input_event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
      input_event_sink_;
  HWND input_window_ = nullptr;
  bool key_states_[256] = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
