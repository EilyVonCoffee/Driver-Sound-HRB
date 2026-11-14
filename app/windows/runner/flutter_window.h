#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/event_sink.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <atomic>
#include <memory>
#include <thread>

#include "../../../platform/windows/audio/EndpointNotificationClient.h"
#include "../../../platform/windows/audio/WasapiToneEngine.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static void OnAudioEndpointEvent(
      void* context,
      const iem::windows_audio::EndpointEvent& event) noexcept;
  void StartAudioRouteWatcher();
  void StopAudioRouteWatcher();
  void PublishDefaultAudioRoute();
  void HandleAudioEngineCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> audio_route_sink_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> audio_engine_channel_;
  std::unique_ptr<iem::windows_audio::WasapiToneEngine> audio_engine_;
  std::thread audio_route_thread_;
  HANDLE audio_route_stop_event_ = nullptr;
  std::atomic<bool> audio_route_watcher_running_{false};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
