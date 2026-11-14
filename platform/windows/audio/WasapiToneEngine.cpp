#include "WasapiToneEngine.h"

#include <audioclient.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <vector>

namespace iem::windows_audio {
namespace {

using Microsoft::WRL::ComPtr;
constexpr float kPi = 3.14159265358979323846F;
constexpr DWORD kEventTimeoutMs = 250;
constexpr float kToneAmplitude = 0.12F;

struct CoTaskMemDeleter {
    void operator()(WAVEFORMATEX* value) const noexcept { CoTaskMemFree(value); }
};

enum class SampleEncoding { Float32, Pcm16, Pcm24, Pcm32, Unsupported };

SampleEncoding GetEncoding(const WAVEFORMATEX* format) noexcept {
    if (format == nullptr) return SampleEncoding::Unsupported;
    auto subFormat = GUID_NULL;
    if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
        format->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
        subFormat = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format)->SubFormat;
    }

    const bool isFloat = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
        (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
         IsEqualGUID(subFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT));
    if (isFloat && format->wBitsPerSample == 32U) return SampleEncoding::Float32;

    const bool isPcm = format->wFormatTag == WAVE_FORMAT_PCM ||
        (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
         IsEqualGUID(subFormat, KSDATAFORMAT_SUBTYPE_PCM));
    if (!isPcm) return SampleEncoding::Unsupported;
    switch (format->wBitsPerSample) {
        case 16: return SampleEncoding::Pcm16;
        case 24: return SampleEncoding::Pcm24;
        case 32: return SampleEncoding::Pcm32;
        default: return SampleEncoding::Unsupported;
    }
}

float SanitizeFrequency(float frequencyHz) noexcept {
    return std::isfinite(frequencyHz)
        ? std::clamp(frequencyHz, 20.0F, 20000.0F)
        : 1000.0F;
}

float PinkNoiseSample(std::array<float, 7>& filter, std::uint32_t& randomState) noexcept {
    randomState ^= randomState << 13;
    randomState ^= randomState >> 17;
    randomState ^= randomState << 5;
    const auto white = static_cast<float>(randomState & 0x7fffffffU) /
                           1073741824.0F -
                       1.0F;
    filter[0] = 0.99886F * filter[0] + white * 0.0555179F;
    filter[1] = 0.99332F * filter[1] + white * 0.0750759F;
    filter[2] = 0.96900F * filter[2] + white * 0.1538520F;
    filter[3] = 0.86650F * filter[3] + white * 0.3104856F;
    filter[4] = 0.55000F * filter[4] + white * 0.5329522F;
    filter[5] = -0.7616F * filter[5] - white * 0.0168980F;
    const auto pink = (filter[0] + filter[1] + filter[2] + filter[3] +
                       filter[4] + filter[5] + filter[6] + white * 0.5362F) *
                      0.11F;
    filter[6] = white * 0.115926F;
    return std::clamp(pink, -1.0F, 1.0F);
}

void ConvertToPcm(const float* source,
                  BYTE* destination,
                  std::size_t sampleCount,
                  SampleEncoding encoding) noexcept {
    if (encoding == SampleEncoding::Float32) {
        std::memcpy(destination, source, sampleCount * sizeof(float));
        return;
    }

    for (std::size_t index = 0; index < sampleCount; ++index) {
        const auto value = std::clamp(source[index], -1.0F, 1.0F);
        if (encoding == SampleEncoding::Pcm16) {
            const auto sample = static_cast<std::int16_t>(std::lrint(value * 32767.0F));
            std::memcpy(destination + index * sizeof(sample), &sample, sizeof(sample));
        } else if (encoding == SampleEncoding::Pcm24) {
            const auto sample = static_cast<std::int32_t>(std::lrint(value * 8388607.0F));
            auto* bytes = destination + index * 3U;
            bytes[0] = static_cast<BYTE>(sample & 0xff);
            bytes[1] = static_cast<BYTE>((sample >> 8) & 0xff);
            bytes[2] = static_cast<BYTE>((sample >> 16) & 0xff);
        } else if (encoding == SampleEncoding::Pcm32) {
            const auto sample = static_cast<std::int32_t>(
                static_cast<double>(value) * 2147483647.0);
            std::memcpy(destination + index * sizeof(sample), &sample, sizeof(sample));
        }
    }
}

}  // namespace

WasapiToneEngine::~WasapiToneEngine() {
    Stop();
}

bool WasapiToneEngine::Start(float frequencyHz, bool pinkNoise) noexcept {
    std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
    frequencyHz_.store(SanitizeFrequency(frequencyHz), std::memory_order_relaxed);
    pinkNoise_.store(pinkNoise, std::memory_order_relaxed);
    if (running_.load(std::memory_order_acquire)) return true;

    if (worker_.joinable()) worker_.join();
    const auto staleEvent = audioEvent_.exchange(nullptr, std::memory_order_acq_rel);
    if (staleEvent != nullptr) CloseHandle(staleEvent);

    const auto event = CreateEvent(nullptr, FALSE, FALSE, nullptr);
    if (event == nullptr) return false;
    audioEvent_.store(event, std::memory_order_release);
    {
        std::lock_guard<std::mutex> startupLock(startupMutex_);
        startupComplete_ = false;
        startupSucceeded_ = false;
    }
    running_.store(true, std::memory_order_release);
    try {
        worker_ = std::thread(&WasapiToneEngine::Run, this);
    } catch (...) {
        running_.store(false, std::memory_order_release);
        audioEvent_.store(nullptr, std::memory_order_release);
        CloseHandle(event);
        return false;
    }

    bool started = false;
    {
        std::unique_lock<std::mutex> startupLock(startupMutex_);
        if (startupCondition_.wait_for(startupLock, std::chrono::seconds(8),
                                        [this] { return startupComplete_; })) {
            started = startupSucceeded_;
        }
    }
    if (!started) {
        running_.store(false, std::memory_order_release);
        SetEvent(event);
        if (worker_.joinable()) worker_.join();
        audioEvent_.store(nullptr, std::memory_order_release);
        CloseHandle(event);
        return false;
    }

    return true;
}

void WasapiToneEngine::Stop() noexcept {
    std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
    running_.store(false, std::memory_order_release);
    const auto event = audioEvent_.load(std::memory_order_acquire);
    if (event != nullptr) SetEvent(event);
    if (worker_.joinable()) worker_.join();
    spectrum_.Stop();
    sampleRate_.store(0, std::memory_order_release);
    audioEvent_.store(nullptr, std::memory_order_release);
    if (event != nullptr) CloseHandle(event);
}

bool WasapiToneEngine::SetFrequency(float frequencyHz) noexcept {
    if (!std::isfinite(frequencyHz)) return false;
    frequencyHz_.store(SanitizeFrequency(frequencyHz), std::memory_order_relaxed);
    return true;
}

bool WasapiToneEngine::SetPinkNoise(bool enabled) noexcept {
    pinkNoise_.store(enabled, std::memory_order_relaxed);
    return true;
}

bool WasapiToneEngine::IsRunning() const noexcept {
    return running_.load(std::memory_order_acquire) &&
           sampleRate_.load(std::memory_order_acquire) > 0;
}

void WasapiToneEngine::ReadSpectrum(float* destination, std::size_t count) const noexcept {
    spectrum_.ReadDb(destination, count);
}

void WasapiToneEngine::SignalStartup(bool succeeded) noexcept {
    {
        std::lock_guard<std::mutex> startupLock(startupMutex_);
        startupSucceeded_ = succeeded;
        startupComplete_ = true;
    }
    startupCondition_.notify_one();
}

void WasapiToneEngine::Run() noexcept {
    const auto comResult = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool ownsCom = SUCCEEDED(comResult);
    if (FAILED(comResult) && comResult != RPC_E_CHANGED_MODE) {
        SignalStartup(false);
        running_.store(false, std::memory_order_release);
        return;
    }

    ComPtr<IMMDeviceEnumerator> enumerator;
    ComPtr<IMMDevice> device;
    ComPtr<IAudioClient> audioClient;
    ComPtr<IAudioRenderClient> renderClient;
    WAVEFORMATEX* rawFormat = nullptr;
    bool analyzerStarted = false;

    HRESULT result = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                      CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    if (SUCCEEDED(result)) {
        result = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    }
    if (SUCCEEDED(result)) {
        result = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                  reinterpret_cast<void**>(audioClient.GetAddressOf()));
    }
    if (SUCCEEDED(result)) result = audioClient->GetMixFormat(&rawFormat);
    std::unique_ptr<WAVEFORMATEX, CoTaskMemDeleter> format(rawFormat);
    const auto encoding = GetEncoding(format.get());
    if (SUCCEEDED(result) && encoding == SampleEncoding::Unsupported) {
        result = AUDCLNT_E_UNSUPPORTED_FORMAT;
    }

    constexpr DWORD streamFlags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
    if (SUCCEEDED(result)) {
        result = audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, streamFlags,
                                         0, 0, format.get(), nullptr);
    }
    const auto event = audioEvent_.load(std::memory_order_acquire);
    if (SUCCEEDED(result) && event == nullptr) result = E_HANDLE;
    if (SUCCEEDED(result)) result = audioClient->SetEventHandle(event);
    UINT32 bufferFrames = 0;
    if (SUCCEEDED(result)) result = audioClient->GetBufferSize(&bufferFrames);
    if (SUCCEEDED(result)) {
        result = audioClient->GetService(IID_PPV_ARGS(&renderClient));
    }

    const auto channels = format == nullptr ? 0U : format->nChannels;
    const auto sampleRate = format == nullptr ? 0U : format->nSamplesPerSec;
    if (SUCCEEDED(result) &&
        (channels == 0U || channels > 8U || sampleRate < 8000U || sampleRate > 384000U ||
         format->nBlockAlign == 0U || bufferFrames == 0U)) {
        result = AUDCLNT_E_UNSUPPORTED_FORMAT;
    }

    std::vector<float> pcm;
    if (SUCCEEDED(result)) {
        try {
            pcm.resize(static_cast<std::size_t>(bufferFrames) * channels);
        } catch (...) {
            result = E_OUTOFMEMORY;
        }
    }

    if (SUCCEEDED(result)) {
        sampleRate_.store(static_cast<int>(sampleRate), std::memory_order_release);
        spectrum_.SetSampleRate(static_cast<float>(sampleRate));
        if (!spectrum_.Start()) {
            result = E_OUTOFMEMORY;
        } else {
            analyzerStarted = true;
            result = audioClient->Start();
        }
    }
    SignalStartup(SUCCEEDED(result));

    float phase = 0.0F;
    std::array<float, 7> pinkFilter{};
    std::uint32_t randomState = 0x1234567U;
    while (SUCCEEDED(result) && running_.load(std::memory_order_acquire)) {
        const auto waitResult = WaitForSingleObject(event, kEventTimeoutMs);
        if (waitResult == WAIT_TIMEOUT) continue;
        if (waitResult != WAIT_OBJECT_0 || !running_.load(std::memory_order_acquire)) break;

        UINT32 padding = 0;
        result = audioClient->GetCurrentPadding(&padding);
        if (FAILED(result)) break;
        if (padding >= bufferFrames) continue;
        const auto availableFrames = bufferFrames - padding;

        auto* destination = static_cast<BYTE*>(nullptr);
        result = renderClient->GetBuffer(availableFrames, &destination);
        if (FAILED(result) || destination == nullptr) break;

        const auto frequency = std::min(
            frequencyHz_.load(std::memory_order_relaxed),
            static_cast<float>(sampleRate) * 0.45F);
        const auto phaseStep = 2.0F * kPi * frequency / static_cast<float>(sampleRate);
        const auto usePinkNoise = pinkNoise_.load(std::memory_order_relaxed);
        const auto sampleCount = static_cast<std::size_t>(availableFrames) * channels;
        for (UINT32 frame = 0; frame < availableFrames; ++frame) {
            float sample;
            if (usePinkNoise) {
                sample = kToneAmplitude * PinkNoiseSample(pinkFilter, randomState);
            } else {
                sample = kToneAmplitude * std::sin(phase);
                phase += phaseStep;
                if (phase >= 2.0F * kPi) phase -= 2.0F * kPi;
            }
            for (UINT32 channel = 0; channel < channels; ++channel) {
                pcm[static_cast<std::size_t>(frame) * channels + channel] = sample;
            }
        }
        for (auto& sample : pcm) sample = std::clamp(sample, -0.89F, 0.89F);
        spectrum_.PushInterleaved(pcm.data(), availableFrames, channels);
        ConvertToPcm(pcm.data(), destination, sampleCount, encoding);
        result = renderClient->ReleaseBuffer(availableFrames, 0);
        if (FAILED(result)) break;
    }

    if (audioClient.Get() != nullptr) (void)audioClient->Stop();
    if (analyzerStarted) spectrum_.Stop();
    sampleRate_.store(0, std::memory_order_release);
    running_.store(false, std::memory_order_release);
    if (ownsCom) CoUninitialize();
}

}  // namespace iem::windows_audio
