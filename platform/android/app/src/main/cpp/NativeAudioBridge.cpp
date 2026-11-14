#include "AudioEngine.h"

#include <jni.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>

namespace {

constexpr float kPi = 3.14159265358979323846F;

class TestToneSource final : public iem::android::AudioSource {
public:
    void SetFrequency(float frequencyHz) noexcept {
        if (std::isfinite(frequencyHz)) {
            frequencyHz_.store(std::clamp(frequencyHz, 20.0F, 20000.0F),
                               std::memory_order_relaxed);
        }
    }

    void SetPinkNoise(bool enabled) noexcept {
        pinkNoise_.store(enabled, std::memory_order_relaxed);
    }

    bool Render(float* output, int32_t frames, int32_t channels) noexcept override {
        if (output == nullptr || frames < 0 || channels < 1 || channels > 2) return false;
        const auto sampleRate = sampleRate_.load(std::memory_order_relaxed);
        if (sampleRate < 8000) return false;

        const auto frequency = std::min(
            frequencyHz_.load(std::memory_order_relaxed),
            static_cast<float>(sampleRate) * 0.45F);
        const auto phaseStep = 2.0F * kPi * frequency / static_cast<float>(sampleRate);
        for (int32_t frame = 0; frame < frames; ++frame) {
            float sample;
            if (pinkNoise_.load(std::memory_order_relaxed)) {
                sample = NextPinkSample() * 0.12F;
            } else {
                sample = 0.12F * std::sin(phase_);
                phase_ += phaseStep;
                if (phase_ >= 2.0F * kPi) phase_ -= 2.0F * kPi;
            }
            for (int32_t channel = 0; channel < channels; ++channel) {
                output[static_cast<std::size_t>(frame) * channels + channel] = sample;
            }
        }
        return true;
    }

    void SetSampleRate(int32_t sampleRate) noexcept override {
        sampleRate_.store(sampleRate, std::memory_order_relaxed);
    }

private:
    float NextPinkSample() noexcept {
        randomState_ ^= randomState_ << 13;
        randomState_ ^= randomState_ >> 17;
        randomState_ ^= randomState_ << 5;
        const auto white = static_cast<float>(randomState_ & 0x7fffffffU) /
                               1073741824.0F -
                           1.0F;
        pink_[0] = 0.99886F * pink_[0] + white * 0.0555179F;
        pink_[1] = 0.99332F * pink_[1] + white * 0.0750759F;
        pink_[2] = 0.96900F * pink_[2] + white * 0.1538520F;
        pink_[3] = 0.86650F * pink_[3] + white * 0.3104856F;
        pink_[4] = 0.55000F * pink_[4] + white * 0.5329522F;
        pink_[5] = -0.7616F * pink_[5] - white * 0.0168980F;
        const auto output = (pink_[0] + pink_[1] + pink_[2] + pink_[3] +
                             pink_[4] + pink_[5] + pink_[6] + white * 0.5362F) *
                            0.11F;
        pink_[6] = white * 0.115926F;
        return std::clamp(output, -1.0F, 1.0F);
    }

    std::atomic<float> frequencyHz_{1000.0F};
    std::atomic<int32_t> sampleRate_{0};
    std::atomic<bool> pinkNoise_{false};
    std::array<float, 7> pink_{};
    std::uint32_t randomState_{0x1234567U};
    float phase_{0.0F};
};

struct NativeHost final {
    NativeHost() noexcept : engine(source) {}
    TestToneSource source;
    iem::android::AudioEngine engine;
};

std::mutex gHostMutex;
std::unique_ptr<NativeHost> gHost;

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_io_iemdriver_iem_1driver_MainActivity_nativeStartTestTone(
    JNIEnv*, jobject, jfloat frequencyHz, jboolean pinkNoise) {
    std::lock_guard<std::mutex> lock(gHostMutex);
    if (gHost && gHost->engine.SampleRate() > 0) {
        gHost->source.SetFrequency(frequencyHz);
        gHost->source.SetPinkNoise(pinkNoise == JNI_TRUE);
        return JNI_TRUE;
    }
    gHost.reset();
    auto candidate = std::make_unique<NativeHost>();
    candidate->source.SetFrequency(frequencyHz);
    candidate->source.SetPinkNoise(pinkNoise == JNI_TRUE);
    const auto result = candidate->engine.Start();
    if (result != oboe::Result::OK) return JNI_FALSE;
    gHost = std::move(candidate);
    return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_io_iemdriver_iem_1driver_MainActivity_nativeStopTestAudio(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gHostMutex);
    gHost.reset();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_io_iemdriver_iem_1driver_MainActivity_nativeSetTestFrequency(
    JNIEnv*, jobject, jfloat frequencyHz) {
    std::lock_guard<std::mutex> lock(gHostMutex);
    if (!gHost) return JNI_FALSE;
    gHost->source.SetFrequency(frequencyHz);
    return JNI_TRUE;
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_io_iemdriver_iem_1driver_MainActivity_nativeReadSpectrum(JNIEnv* env, jobject) {
    std::array<float, iem::kSpectrumBinCount> bins{};
    {
        std::lock_guard<std::mutex> lock(gHostMutex);
        if (gHost) gHost->engine.ReadSpectrumDb(bins.data(), bins.size());
        else bins.fill(-72.0F);
    }
    auto* result = env->NewFloatArray(static_cast<jsize>(bins.size()));
    if (result != nullptr) {
        env->SetFloatArrayRegion(result, 0, static_cast<jsize>(bins.size()), bins.data());
    }
    return result;
}

extern "C" JNIEXPORT jint JNICALL
Java_io_iemdriver_iem_1driver_MainActivity_nativeCurrentDeviceId(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gHostMutex);
    return gHost ? gHost->engine.CurrentDeviceId() : -1;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_io_iemdriver_iem_1driver_MainActivity_nativeIsAudioActive(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gHostMutex);
    return gHost && gHost->engine.SampleRate() > 0 ? JNI_TRUE : JNI_FALSE;
}
