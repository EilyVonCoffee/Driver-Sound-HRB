#pragma once

#include "iem/SpectrumAnalyzer.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <mutex>
#include <thread>

namespace iem::windows_audio {

// Read-only WASAPI loopback capture of the current default render endpoint.
class WasapiLoopbackCapture final {
public:
    WasapiLoopbackCapture() = default;
    ~WasapiLoopbackCapture();

    WasapiLoopbackCapture(const WasapiLoopbackCapture&) = delete;
    WasapiLoopbackCapture& operator=(const WasapiLoopbackCapture&) = delete;

    bool Start() noexcept;
    void Stop() noexcept;
    bool IsRunning() const noexcept;
    void ReadSpectrum(float* destination, std::size_t count) const noexcept;

private:
    void Run() noexcept;
    void SignalStartup(bool succeeded) noexcept;

    std::atomic<bool> running_{false};
    std::atomic<int> sampleRate_{0};
    std::atomic<HANDLE> audioEvent_{nullptr};
    SpectrumAnalyzer spectrum_{};
    std::mutex lifecycleMutex_;
    std::mutex startupMutex_;
    std::condition_variable startupCondition_;
    bool startupComplete_{false};
    bool startupSucceeded_{false};
    std::thread worker_{};
};

}  // namespace iem::windows_audio
