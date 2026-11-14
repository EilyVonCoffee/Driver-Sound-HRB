#pragma once

#include "iem/SpectrumAnalyzer.h"

#include <oboe/Oboe.h>

#include <atomic>
#include <memory>

namespace iem::android {

// AudioSource must render app-owned PCM without locks, allocation, I/O, or UI calls.
class AudioSource {
public:
    virtual ~AudioSource() = default;
    virtual void SetSampleRate(int32_t) noexcept {}
    virtual bool Render(float* interleavedOutput,
                        int32_t frames,
                        int32_t channels) noexcept = 0;
};

class AudioEngine final : public oboe::AudioStreamDataCallback,
                          public oboe::AudioStreamErrorCallback,
                          public oboe::AudioStreamRoutingCallback {
public:
    explicit AudioEngine(AudioSource& source) noexcept;
    ~AudioEngine() override;

    AudioEngine(const AudioEngine&) = delete;
    AudioEngine& operator=(const AudioEngine&) = delete;

    oboe::Result Start();
    void Stop() noexcept;
    bool ConsumeRestartRequest() noexcept;
    int32_t SampleRate() const noexcept;
    int32_t CurrentDeviceId() const noexcept;
    void ReadSpectrumDb(float* destination, std::size_t count) const noexcept;

    oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream,
                                          void* audioData,
                                          int32_t numFrames) override;
    void onErrorBeforeClose(oboe::AudioStream* stream, oboe::Result error) override;
    void onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) override;
    void onRoutingChanged(oboe::AudioStream* stream,
                          const int32_t* deviceIds,
                          int32_t numDevices) override;

private:
    AudioSource& source_;
    // Oboe retains routing callbacks through shared_ptr; AudioEngine owns the lifetime.
    std::shared_ptr<oboe::AudioStreamRoutingCallback> routingCallback_{};
    SpectrumAnalyzer spectrum_{};
    std::shared_ptr<oboe::AudioStream> stream_{};
    std::atomic<int32_t> sampleRate_{0};
    std::atomic<int32_t> currentDeviceId_{-1};
    std::atomic<bool> restartRequested_{false};
};

}  // namespace iem::android
