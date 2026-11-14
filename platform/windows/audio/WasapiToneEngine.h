#pragma once

#include "iem/SpectrumAnalyzer.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <thread>

namespace iem::windows_audio {

// App-owned low-level test signal routed to the current Windows playback
// endpoint. This is not a system-wide APO or virtual audio device.
class WasapiToneEngine final {
public:
    WasapiToneEngine() = default;
    ~WasapiToneEngine();

    WasapiToneEngine(const WasapiToneEngine&) = delete;
    WasapiToneEngine& operator=(const WasapiToneEngine&) = delete;

    bool Start(float frequencyHz, bool pinkNoise = false) noexcept;
    void Stop() noexcept;
    bool SetFrequency(float frequencyHz) noexcept;
    bool SetPinkNoise(bool enabled) noexcept;
    bool IsRunning() const noexcept;
    void ReadSpectrum(float* destination, std::size_t count) const noexcept;

private:
    void Run() noexcept;
    void SignalStartup(bool succeeded) noexcept;

    std::atomic<bool> running_{false};
    std::atomic<float> frequencyHz_{1000.0F};
    std::atomic<bool> pinkNoise_{false};
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
