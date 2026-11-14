#include "AudioEngine.h"

#include <algorithm>
#include <cstring>

namespace iem::android {

AudioEngine::AudioEngine(AudioSource& source) noexcept
    : source_(source),
      routingCallback_(this, [](oboe::AudioStreamRoutingCallback*) noexcept {}) {}

AudioEngine::~AudioEngine() {
    Stop();
}

oboe::Result AudioEngine::Start() {
    if (stream_) return oboe::Result::ErrorInvalidState;

    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Output)
        ->setFormat(oboe::AudioFormat::Float)
        ->setChannelCount(2)
        ->setSharingMode(oboe::SharingMode::Shared)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setDataCallback(this)
        ->setErrorCallback(this)
        ->setRoutingCallback(routingCallback_);

    auto result = builder.openStream(stream_);
    if (result != oboe::Result::OK) return result;

    sampleRate_.store(stream_->getSampleRate(), std::memory_order_release);
    currentDeviceId_.store(stream_->getDeviceId(), std::memory_order_release);
    source_.SetSampleRate(stream_->getSampleRate());
    spectrum_.SetSampleRate(static_cast<float>(stream_->getSampleRate()));
    if (!spectrum_.Start()) {
        Stop();
        return oboe::Result::ErrorInternal;
    }
    result = stream_->requestStart();
    if (result != oboe::Result::OK) {
        Stop();
    }
    return result;
}

void AudioEngine::Stop() noexcept {
    sampleRate_.store(0, std::memory_order_release);
    currentDeviceId_.store(-1, std::memory_order_release);
    if (stream_) {
        (void)stream_->requestStop();
        (void)stream_->close();
        stream_.reset();
    }
    spectrum_.Stop();
}

bool AudioEngine::ConsumeRestartRequest() noexcept {
    return restartRequested_.exchange(false, std::memory_order_acq_rel);
}

int32_t AudioEngine::SampleRate() const noexcept {
    return sampleRate_.load(std::memory_order_acquire);
}

int32_t AudioEngine::CurrentDeviceId() const noexcept {
    return currentDeviceId_.load(std::memory_order_acquire);
}

void AudioEngine::ReadSpectrumDb(float* destination, std::size_t count) const noexcept {
    spectrum_.ReadDb(destination, count);
}

oboe::DataCallbackResult AudioEngine::onAudioReady(oboe::AudioStream* stream,
                                                    void* audioData,
                                                    int32_t numFrames) {
    auto* output = static_cast<float*>(audioData);
    const auto channels = static_cast<std::size_t>(stream->getChannelCount());
    const auto frames = static_cast<std::size_t>(std::max(numFrames, 0));
    if (!source_.Render(output, numFrames, static_cast<int32_t>(channels))) {
        std::fill(output, output + frames * channels, 0.0F);
    }
    for (std::size_t index = 0; index < frames * channels; ++index) {
        output[index] = std::clamp(output[index], -0.89F, 0.89F);
    }
    spectrum_.PushInterleaved(output, frames, channels);
    return oboe::DataCallbackResult::Continue;
}

void AudioEngine::onErrorBeforeClose(oboe::AudioStream*, oboe::Result) {}

void AudioEngine::onErrorAfterClose(oboe::AudioStream*, oboe::Result) {
    // Reopen on a control thread. Never tear down/reopen the stream from this callback.
    sampleRate_.store(0, std::memory_order_release);
    currentDeviceId_.store(-1, std::memory_order_release);
    restartRequested_.store(true, std::memory_order_release);
}

void AudioEngine::onRoutingChanged(oboe::AudioStream*,
                                   const int32_t* deviceIds,
                                   int32_t numDevices) {
    const auto deviceId = deviceIds != nullptr && numDevices > 0 ? deviceIds[0] : -1;
    currentDeviceId_.store(deviceId, std::memory_order_release);
}

}  // namespace iem::android
