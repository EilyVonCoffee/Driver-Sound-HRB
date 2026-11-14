#include "flutter_window.h"

#include <algorithm>
#include <array>
#include <cwctype>
#include <string>
#include <optional>
#include <cmath>
#include <vector>

#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <propsys.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kAudioRouteChangedMessage = WM_APP + 1;
constexpr char kAudioRouteChannel[] = "iem_driver/audio_routes";
constexpr char kAudioEngineChannel[] = "iem_driver/audio_engine";

const flutter::EncodableValue* FindValue(
    const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

bool ReadNumber(const flutter::EncodableValue* value, double* result) {
  if (value == nullptr || result == nullptr) return false;
  const auto* variant = static_cast<const flutter::EncodableValue::super*>(value);
  if (const auto* number = std::get_if<double>(variant)) {
    *result = *number;
    return std::isfinite(*result);
  }
  if (const auto integer = value->TryGetLongValue()) {
    *result = static_cast<double>(*integer);
    return true;
  }
  return false;
}

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int required = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                           static_cast<int>(value.size()),
                                           nullptr, 0, nullptr, nullptr);
  if (required <= 0) return {};
  std::string result(static_cast<std::size_t>(required), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), required,
                      nullptr, nullptr);
  return result;
}

std::string EndpointKind(const std::wstring& endpoint_name,
                         const std::wstring& endpoint_id) {
  auto searchable = endpoint_name + L" " + endpoint_id;
  std::transform(searchable.begin(), searchable.end(), searchable.begin(),
                 [](wchar_t value) { return static_cast<wchar_t>(towlower(value)); });
  if (searchable.find(L"usb") != std::wstring::npos) return "usb";
  if (searchable.find(L"bluetooth") != std::wstring::npos) return "bluetooth";
  if (searchable.find(L"headphone") != std::wstring::npos ||
      searchable.find(L"headset") != std::wstring::npos ||
      searchable.find(L"wired") != std::wstring::npos) {
    return "jack";
  }
  return "other";
}
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

  flutter::EventChannel<flutter::EncodableValue> route_channel(
      flutter_controller_->engine()->messenger(), kAudioRouteChannel,
      &flutter::StandardMethodCodec::GetInstance());
  route_channel.SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
            audio_route_sink_ = std::move(events);
            PublishDefaultAudioRoute();
            StartAudioRouteWatcher();
            return std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>{};
          },
          [this](const flutter::EncodableValue*) {
            StopAudioRouteWatcher();
            audio_route_sink_.reset();
            return std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>{};
          }));

  audio_engine_ = std::make_unique<iem::windows_audio::WasapiToneEngine>();
  audio_engine_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kAudioEngineChannel,
      &flutter::StandardMethodCodec::GetInstance());
  audio_engine_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleAudioEngineCall(call, std::move(result));
      });

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
  StopAudioRouteWatcher();
  audio_route_sink_.reset();
  if (audio_engine_channel_) audio_engine_channel_->SetMethodCallHandler(nullptr);
  audio_engine_channel_.reset();
  if (audio_engine_) audio_engine_->Stop();
  audio_engine_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleAudioEngineCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!audio_engine_) {
    result->Error("audio_unavailable", "The Windows audio engine is not initialized.");
    return;
  }

  const auto* arguments = call.arguments();
  const auto* map = arguments == nullptr
      ? nullptr
      : std::get_if<flutter::EncodableMap>(
            static_cast<const flutter::EncodableValue::super*>(arguments));

  if (call.method_name() == "startTestTone") {
    double requestedFrequency = 1000.0;
    bool pinkNoise = false;
    if (map != nullptr) {
      const auto* value = FindValue(*map, "frequencyHz");
      if (value != nullptr && !ReadNumber(value, &requestedFrequency)) {
        result->Error("invalid_frequency", "Test frequency must be numeric.");
        return;
      }
      const auto* pinkNoiseValue = FindValue(*map, "pinkNoise");
      if (pinkNoiseValue != nullptr) {
        const auto* encoded = static_cast<const flutter::EncodableValue::super*>(pinkNoiseValue);
        const auto* boolean = std::get_if<bool>(encoded);
        if (boolean == nullptr) {
          result->Error("invalid_noise_mode", "Pink noise mode must be boolean.");
          return;
        }
        pinkNoise = *boolean;
      }
    }
    const auto started = audio_engine_->Start(
        static_cast<float>(requestedFrequency), pinkNoise);
    if (started) result->Success(flutter::EncodableValue(true));
    else result->Error("audio_output_unavailable",
                       "Could not open a supported Windows playback endpoint.");
    return;
  }

  if (call.method_name() == "stopTestAudio") {
    audio_engine_->Stop();
    result->Success();
    return;
  }

  if (call.method_name() == "isTestAudioActive") {
    result->Success(flutter::EncodableValue(audio_engine_->IsRunning()));
    return;
  }

  if (call.method_name() == "setTestFrequency") {
    double frequency = 0.0;
    if (map == nullptr || !ReadNumber(FindValue(*map, "frequencyHz"), &frequency) ||
        frequency < 20.0 || frequency > 20000.0) {
      result->Error("invalid_frequency", "Test frequency must be between 20 Hz and 20 kHz.");
      return;
    }
    result->Success(flutter::EncodableValue(
        audio_engine_->SetFrequency(static_cast<float>(frequency))));
    return;
  }

  if (call.method_name() == "readSpectrum") {
    std::array<float, iem::kSpectrumBinCount> bins{};
    audio_engine_->ReadSpectrum(bins.data(), bins.size());
    flutter::EncodableList resultBins;
    resultBins.reserve(bins.size());
    for (const auto value : bins) resultBins.emplace_back(static_cast<double>(value));
    result->Success(flutter::EncodableValue(std::move(resultBins)));
    return;
  }

  result->NotImplemented();
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
    case kAudioRouteChangedMessage:
      PublishDefaultAudioRoute();
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::OnAudioEndpointEvent(
    void* context, const iem::windows_audio::EndpointEvent&) noexcept {
  auto* window = static_cast<FlutterWindow*>(context);
  if (window == nullptr) return;
  const HWND handle = window->GetHandle();
  if (handle != nullptr) PostMessage(handle, kAudioRouteChangedMessage, 0, 0);
}

void FlutterWindow::StartAudioRouteWatcher() {
  if (audio_route_thread_.joinable()) return;
  audio_route_stop_event_ = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  if (audio_route_stop_event_ == nullptr) return;
  audio_route_watcher_running_.store(true, std::memory_order_release);
  audio_route_thread_ = std::thread([this]() {
    const HRESULT com_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(com_result)) {
      audio_route_watcher_running_.store(false, std::memory_order_release);
      return;
    }

    iem::windows_audio::EndpointWatcher watcher;
    const HRESULT start_result = watcher.Start(&FlutterWindow::OnAudioEndpointEvent, this);
    if (SUCCEEDED(start_result)) {
      PostMessage(GetHandle(), kAudioRouteChangedMessage, 0, 0);
      WaitForSingleObject(audio_route_stop_event_, INFINITE);
      watcher.Stop();
    }
    audio_route_watcher_running_.store(false, std::memory_order_release);
    CoUninitialize();
  });
}

void FlutterWindow::StopAudioRouteWatcher() {
  if (audio_route_stop_event_ != nullptr) SetEvent(audio_route_stop_event_);
  if (audio_route_thread_.joinable()) audio_route_thread_.join();
  if (audio_route_stop_event_ != nullptr) {
    CloseHandle(audio_route_stop_event_);
    audio_route_stop_event_ = nullptr;
  }
  audio_route_watcher_running_.store(false, std::memory_order_release);
}

void FlutterWindow::PublishDefaultAudioRoute() {
  if (!audio_route_sink_) return;

  flutter::EncodableList outputs;
  std::string active_output_id;
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  LPWSTR endpoint_id = nullptr;
  std::wstring endpoint_name;

  HRESULT result = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                    CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (SUCCEEDED(result)) {
    result = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
  }
  if (SUCCEEDED(result) && device != nullptr) {
    if (SUCCEEDED(device->GetId(&endpoint_id)) && endpoint_id != nullptr) {
      active_output_id = ToUtf8(endpoint_id);
    }
    IPropertyStore* properties = nullptr;
    if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties)) && properties != nullptr) {
      PROPVARIANT friendly_name;
      PropVariantInit(&friendly_name);
      if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &friendly_name)) &&
          friendly_name.vt == VT_LPWSTR && friendly_name.pwszVal != nullptr) {
        endpoint_name = friendly_name.pwszVal;
      }
      PropVariantClear(&friendly_name);
      properties->Release();
    }
    const std::wstring wide_id = endpoint_id == nullptr ? L"" : endpoint_id;
    const std::string name = endpoint_name.empty() ? "Windows playback endpoint"
                                                   : ToUtf8(endpoint_name);
    flutter::EncodableMap route;
    route[flutter::EncodableValue("id")] = flutter::EncodableValue(active_output_id);
    route[flutter::EncodableValue("profileKey")] =
        flutter::EncodableValue("windows:" + active_output_id);
    route[flutter::EncodableValue("kind")] =
        flutter::EncodableValue(EndpointKind(endpoint_name, wide_id));
    route[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
    route[flutter::EncodableValue("active")] = flutter::EncodableValue(true);
    outputs.emplace_back(std::move(route));
  }

  if (endpoint_id != nullptr) CoTaskMemFree(endpoint_id);
  if (device != nullptr) device->Release();
  if (enumerator != nullptr) enumerator->Release();

  flutter::EncodableMap snapshot;
  snapshot[flutter::EncodableValue("availableOutputs")] =
      flutter::EncodableValue(std::move(outputs));
  snapshot[flutter::EncodableValue("activeOutputId")] =
      active_output_id.empty() ? flutter::EncodableValue()
                               : flutter::EncodableValue(active_output_id);
  audio_route_sink_->Success(flutter::EncodableValue(std::move(snapshot)));
}
