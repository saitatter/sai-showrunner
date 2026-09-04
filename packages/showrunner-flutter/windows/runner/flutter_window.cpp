#include "flutter_window.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kInputMethodChannel[] = "showrunner/input";
constexpr char kInputEventChannel[] = "showrunner/input/events";
constexpr wchar_t kInputWindowClassName[] = L"SHOWRUNNER_INPUT_EVENT_WINDOW";

std::optional<int> ReadIntegerArgument(
    const flutter::EncodableValue* arguments, const char* name) {
  if (arguments == nullptr ||
      !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    return std::nullopt;
  }
  const auto& map = std::get<flutter::EncodableMap>(*arguments);
  const auto iterator = map.find(
      flutter::EncodableValue(std::string(name)));
  if (iterator == map.end()) return std::nullopt;
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    if (*value < INT32_MIN || *value > INT32_MAX) return std::nullopt;
    return static_cast<int>(*value);
  }
  return std::nullopt;
}

std::optional<std::string> ReadStringArgument(
    const flutter::EncodableValue* arguments, const char* name) {
  if (arguments == nullptr ||
      !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    return std::nullopt;
  }
  const auto& map = std::get<flutter::EncodableMap>(*arguments);
  const auto iterator = map.find(
      flutter::EncodableValue(std::string(name)));
  if (iterator == map.end()) return std::nullopt;
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return std::nullopt;
}

class InputEventStreamHandler final
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit InputEventStreamHandler(FlutterWindow* window) : window_(window) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
      override {
    if (window_->StartInputEvents(std::move(events))) return nullptr;
    return std::make_unique<
        flutter::StreamHandlerError<flutter::EncodableValue>>(
        "input_unavailable", "Unable to register raw keyboard input.",
        std::unique_ptr<flutter::EncodableValue>());
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue* arguments) override {
    window_->StopInputEvents();
    return nullptr;
  }

 private:
  FlutterWindow* window_;
};

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupInputChannels();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (input_event_channel_) {
    input_event_channel_->SetStreamHandler(nullptr);
  }
  if (input_method_channel_) {
    input_method_channel_->SetMethodCallHandler(nullptr);
  }
  StopInputEvents();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetupInputChannels() {
  auto* messenger = flutter_controller_->engine()->messenger();
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();

  input_method_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kInputMethodChannel, codec);
  input_method_channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) { HandleInputMethod(call, std::move(result)); });

  input_event_channel_ = std::make_unique<
      flutter::EventChannel<flutter::EncodableValue>>(
      messenger, kInputEventChannel, codec);
  input_event_channel_->SetStreamHandler(
      std::make_unique<InputEventStreamHandler>(this));
}

void FlutterWindow::HandleInputMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "simulateKeyDown" ||
      call.method_name() == "simulateKeyUp") {
    const auto virtual_key_code =
        ReadIntegerArgument(call.arguments(), "vkCode");
    if (!virtual_key_code.has_value() ||
        !SendKeyInput(*virtual_key_code,
                      call.method_name() == "simulateKeyDown")) {
      result->Error("invalid_input", "Invalid or unavailable virtual key.");
      return;
    }
    result->Success();
    return;
  }

  if (call.method_name() == "simulateMouseDown" ||
      call.method_name() == "simulateMouseUp") {
    const auto button = ReadStringArgument(call.arguments(), "button");
    if (!button.has_value() ||
        !SendMouseInput(*button,
                        call.method_name() == "simulateMouseDown")) {
      result->Error("invalid_input", "Invalid or unavailable mouse button.");
      return;
    }
    result->Success();
    return;
  }

  if (call.method_name() == "startEvents") {
    if (!EnsureInputWindow()) {
      result->Error("input_unavailable",
                    "Unable to register raw keyboard input.");
      return;
    }
    result->Success();
    return;
  }

  if (call.method_name() == "stopEvents") {
    StopInputEvents();
    result->Success();
    return;
  }

  if (call.method_name() == "isKeyDown") {
    const auto virtual_key_code =
        ReadIntegerArgument(call.arguments(), "vkCode");
    if (!virtual_key_code.has_value() || *virtual_key_code < 0 ||
        *virtual_key_code > 255) {
      result->Error("invalid_input", "Invalid virtual key.");
      return;
    }
    result->Success(flutter::EncodableValue(
        key_states_[static_cast<size_t>(*virtual_key_code)]));
    return;
  }

  result->NotImplemented();
}

bool FlutterWindow::StartInputEvents(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  if (!EnsureInputWindow()) return false;
  input_event_sink_ = std::move(sink);
  return true;
}

void FlutterWindow::StopInputEvents() {
  if (input_window_ != nullptr) {
    RAWINPUTDEVICE device{};
    device.usUsagePage = 0x01;
    device.usUsage = 0x06;
    device.dwFlags = RIDEV_REMOVE;
    device.hwndTarget = nullptr;
    RegisterRawInputDevices(&device, 1, sizeof(device));
    DestroyWindow(input_window_);
    input_window_ = nullptr;
  }
  std::fill(std::begin(key_states_), std::end(key_states_), false);
  input_event_sink_.reset();
}

bool FlutterWindow::EnsureInputWindow() {
  if (input_window_ != nullptr) return true;

  HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = &FlutterWindow::InputWindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kInputWindowClassName;
  if (RegisterClassExW(&window_class) == 0 &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }

  input_window_ = CreateWindowExW(
      0, kInputWindowClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
      instance, nullptr);
  if (input_window_ == nullptr) return false;
  SetWindowLongPtrW(input_window_, GWLP_USERDATA,
                    reinterpret_cast<LONG_PTR>(this));

  RAWINPUTDEVICE device{};
  device.usUsagePage = 0x01;
  device.usUsage = 0x06;
  device.dwFlags = RIDEV_INPUTSINK | RIDEV_DEVNOTIFY;
  device.hwndTarget = input_window_;
  if (RegisterRawInputDevices(&device, 1, sizeof(device)) == FALSE) {
    DestroyWindow(input_window_);
    input_window_ = nullptr;
    return false;
  }
  return true;
}

bool FlutterWindow::SendKeyInput(int virtual_key_code, bool pressed) {
  if (virtual_key_code < 0 || virtual_key_code > 255) return false;
  INPUT input{};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = static_cast<WORD>(virtual_key_code);
  if (!pressed) input.ki.dwFlags = KEYEVENTF_KEYUP;
  return SendInput(1, &input, sizeof(input)) == 1;
}

bool FlutterWindow::SendMouseInput(const std::string& button, bool pressed) {
  INPUT input{};
  input.type = INPUT_MOUSE;
  if (button == "left") {
    input.mi.dwFlags = pressed ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
  } else if (button == "right") {
    input.mi.dwFlags = pressed ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
  } else if (button == "middle") {
    input.mi.dwFlags = pressed ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
  } else if (button == "mouse4" || button == "mouse5") {
    input.mi.dwFlags = pressed ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
    input.mi.mouseData = button == "mouse4" ? XBUTTON1 : XBUTTON2;
  } else {
    return false;
  }
  return SendInput(1, &input, sizeof(input)) == 1;
}

void FlutterWindow::HandleInputMessage(LPARAM lparam) {
  UINT size = 0;
  if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT,
                      nullptr, &size, sizeof(RAWINPUTHEADER)) ==
      static_cast<UINT>(-1)) {
    return;
  }
  std::vector<std::uint8_t> buffer(size);
  if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT,
                      buffer.data(), &size, sizeof(RAWINPUTHEADER)) ==
      static_cast<UINT>(-1)) {
    return;
  }
  const auto* input = reinterpret_cast<const RAWINPUT*>(buffer.data());
  if (input->header.dwType != RIM_TYPEKEYBOARD) return;
  const auto& keyboard = input->data.keyboard;
  HandleInputKey(keyboard.VKey, (keyboard.Flags & RI_KEY_BREAK) == 0);
}

void FlutterWindow::HandleInputKey(unsigned int virtual_key_code,
                                   bool pressed) {
  if (virtual_key_code > 255) return;
  const auto index = static_cast<size_t>(virtual_key_code);
  const bool was_pressed = key_states_[index];
  key_states_[index] = pressed;
  if (was_pressed == pressed || input_event_sink_ == nullptr) return;

  flutter::EncodableMap event;
  event.emplace(flutter::EncodableValue(std::string("type")),
                flutter::EncodableValue(std::string(
                    pressed ? "key-pressed" : "key-released")));
  event.emplace(flutter::EncodableValue(std::string("vkCode")),
                flutter::EncodableValue(
                    static_cast<int32_t>(virtual_key_code)));
  input_event_sink_->Success(flutter::EncodableValue(std::move(event)));
}

// static
LRESULT CALLBACK FlutterWindow::InputWindowProc(HWND window, UINT message,
                                                WPARAM wparam,
                                                LPARAM lparam) {
  auto* owner = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (owner != nullptr && message == WM_INPUT) {
    owner->HandleInputMessage(lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
