#include "WasapiLoopbackCapture.h"

#include <audioclient.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <vector>

namespace iem::windows_audio {
namespace {

using Microsoft::WRL::ComPtr;
constexpr DWORD kEventTimeoutMs = 250;

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

float DecodeSample(const BYTE* source, SampleEncoding encoding) noexcept {
    if (source == nullptr) return 0.0F;
    float value = 0.0F;
    switch (encoding) {
        case SampleEncoding::Float32:
            std::memcpy(&value, source, sizeof(value));
            break;
        case SampleEncoding::Pcm16: {
            std::int16_t sample = 0;
            std::memcpy(&sample, source, sizeof(sample));
            value = static_cast<float>(sample) / 32768.0F;
            break;
        }
        case SampleEncoding::Pcm24: {
            std::int32_t sample = static_cast<std::int32_t>(source[0]) |
                (static_cast<std::int32_t>(source[1]) << 8) |
                (static_cast<std::int32_t>(source[2]) << 16);
            if ((sample & 0x00800000) != 0) sample |= static_cast<std::int32_t>(0xff000000);
            value = static_cast<float>(sample) / 8388608.0F;
            break;
        }
        case SampleEncoding::Pcm32: {
            std::int32_t sample = 0;
            std::memcpy(&sample, source, sizeof(sample));
            value = static_cast<float>(static_cast<double>(sample) / 2147483648.0);
            break;
        }
        case SampleEncoding::Unsupported:
            break;
    }
    return std::isfinite(value) ? std::clamp(value, -1.0F, 1.0F) : 0.0F;
}

std::size_t BytesPerSample(SampleEncoding encoding) noexcept {
    switch (encoding) {
        case SampleEncoding::Float32:
        case SampleEncoding::Pcm32: return 4U;
        case SampleEncoding::Pcm24: return 3U;
        case SampleEncoding::Pcm16: return 2U;
        case SampleEncoding::Unsupported: return 0U;
    }
    return 0U;
}

}  // namespace

WasapiLoopbackCapture::~WasapiLoopbackCapture() {
    Stop();
}

bool WasapiLoopbackCapture::Start() noexcept {
    std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
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
        worker_ = std::thread(&WasapiLoopbackCapture::Run, this);
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

void WasapiLoopbackCapture::Stop() noexcept {
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

bool WasapiLoopbackCapture::IsRunning() const noexcept {
    return running_.load(std::memory_order_acquire) &&
           sampleRate_.load(std::memory_order_acquire) > 0;
}

void WasapiLoopbackCapture::ReadSpectrum(float* destination,
                                         std::size_t count) const noexcept {
    spectrum_.ReadDb(destination, count);
}

void WasapiLoopbackCapture::SignalStartup(bool succeeded) noexcept {
    {
        std::lock_guard<std::mutex> startupLock(startupMutex_);
        startupSucceeded_ = succeeded;
        startupComplete_ = true;
    }
    startupCondition_.notify_one();
}

void WasapiLoopbackCapture::Run() noexcept {
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
    ComPtr<IAudioCaptureClient> captureClient;
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

    constexpr DWORD streamFlags = AUDCLNT_STREAMFLAGS_LOOPBACK |
                                  AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
    if (SUCCEEDED(result)) {
        result = audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, streamFlags,
                                         0, 0, format.get(), nullptr);
    }
    const auto event = audioEvent_.load(std::memory_order_acquire);
    if (SUCCEEDED(result) && event == nullptr) result = E_HANDLE;
    if (SUCCEEDED(result)) result = audioClient->SetEventHandle(event);
    UINT32 bufferFrames = 0;
    if (SUCCEEDED(result)) result = audioClient->GetBufferSize(&bufferFrames);
    if (SUCCEEDED(result)) result = audioClient->GetService(IID_PPV_ARGS(&captureClient));

    const auto channels = format == nullptr ? 0U : format->nChannels;
    const auto sampleRate = format == nullptr ? 0U : format->nSamplesPerSec;
    const auto bytesPerSample = BytesPerSample(encoding);
    if (SUCCEEDED(result) &&
        (channels == 0U || channels > 8U || sampleRate < 8000U || sampleRate > 384000U ||
         format->nBlockAlign == 0U || bytesPerSample == 0U || bufferFrames == 0U ||
         format->nBlockAlign < channels * bytesPerSample)) {
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

    while (SUCCEEDED(result) && running_.load(std::memory_order_acquire)) {
        const auto waitResult = WaitForSingleObject(event, kEventTimeoutMs);
        if (waitResult == WAIT_TIMEOUT) continue;
        if (waitResult != WAIT_OBJECT_0 || !running_.load(std::memory_order_acquire)) break;

        UINT32 packetFrames = 0;
        result = captureClient->GetNextPacketSize(&packetFrames);
        while (SUCCEEDED(result) && packetFrames > 0U &&
               running_.load(std::memory_order_acquire)) {
            BYTE* source = nullptr;
            UINT32 frames = 0;
            DWORD flags = 0;
            result = captureClient->GetBuffer(&source, &frames, &flags, nullptr, nullptr);
            if (FAILED(result)) break;
            if (frames > bufferFrames ||
                static_cast<std::size_t>(frames) * channels > pcm.size()) {
                (void)captureClient->ReleaseBuffer(frames);
                result = AUDCLNT_E_BUFFER_ERROR;
                break;
            }

            if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0U) {
                std::fill_n(pcm.begin(), static_cast<std::size_t>(frames) * channels, 0.0F);
            } else if (source == nullptr) {
                (void)captureClient->ReleaseBuffer(frames);
                result = AUDCLNT_E_BUFFER_ERROR;
                break;
            } else {
                for (UINT32 frame = 0; frame < frames; ++frame) {
                    for (UINT32 channel = 0; channel < channels; ++channel) {
                        const auto sampleIndex = static_cast<std::size_t>(frame) * channels + channel;
                        const auto* sample = source + static_cast<std::size_t>(frame) * format->nBlockAlign +
                                             static_cast<std::size_t>(channel) * bytesPerSample;
                        pcm[sampleIndex] = DecodeSample(sample, encoding);
                    }
                }
            }

            spectrum_.PushInterleaved(pcm.data(), frames, channels);
            result = captureClient->ReleaseBuffer(frames);
            if (SUCCEEDED(result)) result = captureClient->GetNextPacketSize(&packetFrames);
        }
    }

    if (audioClient.Get() != nullptr) (void)audioClient->Stop();
    if (analyzerStarted) spectrum_.Stop();
    sampleRate_.store(0, std::memory_order_release);
    running_.store(false, std::memory_order_release);
    if (ownsCom) CoUninitialize();
}

}  // namespace iem::windows_audio
