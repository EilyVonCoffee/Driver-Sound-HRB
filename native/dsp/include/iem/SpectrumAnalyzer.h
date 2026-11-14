#pragma once

#include "iem/LockFreeSpscQueue.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <thread>

namespace iem {

constexpr std::size_t kSpectrumBinCount = 64;
static_assert(std::atomic<float>::is_always_lock_free,
              "Spectrum snapshots require lock-free float atomics");

// Audio-thread producer -> analysis-thread consumer. The FFT and smoothing are
// performed off the real-time thread; UI code polls the atomic dB snapshot.
class SpectrumAnalyzer final {
public:
    explicit SpectrumAnalyzer(float sampleRate = 48000.0F) noexcept;
    ~SpectrumAnalyzer();

    SpectrumAnalyzer(const SpectrumAnalyzer&) = delete;
    SpectrumAnalyzer& operator=(const SpectrumAnalyzer&) = delete;

    bool Start() noexcept;
    void Stop() noexcept;
    // Call only while stopped, before Start().
    void SetSampleRate(float sampleRate) noexcept;

    // Call from exactly one audio callback thread with interleaved float PCM.
    void PushInterleaved(const float* samples,
                         std::size_t frames,
                         std::size_t channels) noexcept;

    void ReadDb(float* destination, std::size_t count) const noexcept;

private:
    static constexpr std::size_t kFftSize = 2048;
    void Run() noexcept;
    void Analyze(const std::array<float, kFftSize>& samples) noexcept;

    float sampleRate_;
    std::size_t hopSize_;
    LockFreeSpscQueue<float, 16384> samples_{};
    std::array<std::atomic<float>, kSpectrumBinCount> spectrumDb_{};
    std::atomic<bool> running_{false};
    std::thread worker_{};
};

}  // namespace iem
