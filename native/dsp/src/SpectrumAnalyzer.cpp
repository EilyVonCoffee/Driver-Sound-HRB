#include "iem/SpectrumAnalyzer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
#include <utility>

namespace iem {
namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr auto kFramePeriod = std::chrono::nanoseconds(16'666'667);
constexpr float kMinimumSampleRate = 8000.0F;
constexpr float kMaximumSampleRate = 384000.0F;

float SanitizeSampleRate(float sampleRate) noexcept {
    return std::isfinite(sampleRate) && sampleRate >= kMinimumSampleRate &&
                   sampleRate <= kMaximumSampleRate
        ? sampleRate
        : 48000.0F;
}

std::size_t CalculateHopSize(float sampleRate) noexcept {
    return std::max<std::size_t>(
        1U, static_cast<std::size_t>(std::lround(sampleRate / 60.0F)));
}

void Fft(std::array<std::complex<double>, 2048>& values) noexcept {
    constexpr std::size_t size = 2048;
    for (std::size_t i = 1, j = 0; i < size; ++i) {
        auto bit = size >> 1U;
        for (; (j & bit) != 0U; bit >>= 1U) {
            j ^= bit;
        }
        j ^= bit;
        if (i < j) {
            std::swap(values[i], values[j]);
        }
    }

    for (std::size_t length = 2; length <= size; length <<= 1U) {
        const auto angle = -2.0 * kPi / static_cast<double>(length);
        const std::complex<double> root(std::cos(angle), std::sin(angle));
        for (std::size_t start = 0; start < size; start += length) {
            std::complex<double> factor(1.0, 0.0);
            const auto half = length >> 1U;
            for (std::size_t offset = 0; offset < half; ++offset) {
                const auto even = values[start + offset];
                const auto odd = values[start + offset + half] * factor;
                values[start + offset] = even + odd;
                values[start + offset + half] = even - odd;
                factor *= root;
            }
        }
    }
}

}  // namespace

SpectrumAnalyzer::SpectrumAnalyzer(float sampleRate) noexcept
    : sampleRate_(SanitizeSampleRate(sampleRate)),
      hopSize_(CalculateHopSize(sampleRate_)) {
    for (auto& value : spectrumDb_) {
        value.store(-72.0F, std::memory_order_relaxed);
    }
}

SpectrumAnalyzer::~SpectrumAnalyzer() {
    Stop();
}

void SpectrumAnalyzer::SetSampleRate(float sampleRate) noexcept {
    if (running_.load(std::memory_order_acquire)) return;
    sampleRate_ = SanitizeSampleRate(sampleRate);
    hopSize_ = CalculateHopSize(sampleRate_);
}

bool SpectrumAnalyzer::Start() noexcept {
    bool expected = false;
    if (!running_.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
        return worker_.joinable();
    }
    try {
        worker_ = std::thread(&SpectrumAnalyzer::Run, this);
        return true;
    } catch (...) {
        running_.store(false, std::memory_order_release);
        return false;
    }
}

void SpectrumAnalyzer::Stop() noexcept {
    running_.store(false, std::memory_order_release);
    if (worker_.joinable()) {
        worker_.join();
    }
}

void SpectrumAnalyzer::PushInterleaved(const float* samples,
                                       std::size_t frames,
                                       std::size_t channels) noexcept {
    if (samples == nullptr || channels == 0U) {
        return;
    }
    for (std::size_t frame = 0; frame < frames; ++frame) {
        double sum = 0.0;
        for (std::size_t channel = 0; channel < channels; ++channel) {
            sum += samples[frame * channels + channel];
        }
        const auto mono = static_cast<float>(sum / static_cast<double>(channels));
        (void)samples_.TryPush(mono);  // Drop newest on overflow; never block audio.
    }
}

void SpectrumAnalyzer::ReadDb(float* destination, std::size_t count) const noexcept {
    if (destination == nullptr) {
        return;
    }
    const auto limit = std::min(count, kSpectrumBinCount);
    for (std::size_t i = 0; i < limit; ++i) {
        destination[i] = spectrumDb_[i].load(std::memory_order_relaxed);
    }
}

void SpectrumAnalyzer::Run() noexcept {
    std::array<float, kFftSize> window{};
    std::size_t filled = 0;
    std::size_t samplesToSkip = 0;
    auto nextFrame = std::chrono::steady_clock::now();

    while (running_.load(std::memory_order_acquire)) {
        float sample = 0.0F;
        while (samplesToSkip > 0U && samples_.TryPop(sample)) {
            --samplesToSkip;
        }
        while (filled < kFftSize && samples_.TryPop(sample)) {
            window[filled++] = sample;
        }

        const auto now = std::chrono::steady_clock::now();
        if (filled == kFftSize && now >= nextFrame) {
            Analyze(window);
            if (hopSize_ < kFftSize) {
                std::move(window.begin() + static_cast<std::ptrdiff_t>(hopSize_),
                          window.end(),
                          window.begin());
                filled -= hopSize_;
            } else {
                filled = 0;
                samplesToSkip = hopSize_ - kFftSize;
            }
            nextFrame += kFramePeriod;
            if (nextFrame < now) {
                nextFrame = now + kFramePeriod;
            }
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }
}

void SpectrumAnalyzer::Analyze(const std::array<float, kFftSize>& samples) noexcept {
    std::array<std::complex<double>, kFftSize> values{};
    for (std::size_t i = 0; i < kFftSize; ++i) {
        const auto hann = 0.5 - 0.5 * std::cos(
            2.0 * kPi * static_cast<double>(i) / static_cast<double>(kFftSize - 1U));
        values[i] = std::complex<double>(static_cast<double>(samples[i]) * hann, 0.0);
    }
    Fft(values);

    for (std::size_t band = 0; band < kSpectrumBinCount; ++band) {
        const auto lowHz = 20.0 * std::pow(1000.0,
                                          static_cast<double>(band) /
                                              static_cast<double>(kSpectrumBinCount));
        const auto highHz = 20.0 * std::pow(1000.0,
                                            static_cast<double>(band + 1U) /
                                                static_cast<double>(kSpectrumBinCount));
        double magnitude = 0.0;
        const auto nyquist = static_cast<double>(sampleRate_) / 2.0;
        if (lowHz < nyquist) {
            const auto lowBin = std::clamp<std::size_t>(
                static_cast<std::size_t>(lowHz * kFftSize / sampleRate_),
                1U,
                kFftSize / 2U);
            const auto cappedHighHz = std::min(highHz, nyquist);
            const auto highBin = std::clamp<std::size_t>(
                static_cast<std::size_t>(std::ceil(cappedHighHz * kFftSize / sampleRate_)),
                lowBin + 1U,
                kFftSize / 2U + 1U);
            std::size_t count = 0;
            for (auto bin = lowBin; bin < highBin; ++bin) {
                magnitude += std::abs(values[bin]) * 4.0 / static_cast<double>(kFftSize);
                ++count;
            }
            magnitude /= static_cast<double>(std::max<std::size_t>(count, 1U));
        }
        const auto db = static_cast<float>(std::clamp(
            20.0 * std::log10(std::max(magnitude, 1.0e-6)), -72.0, 6.0));
        const auto previous = spectrumDb_[band].load(std::memory_order_relaxed);
        const auto coefficient = db > previous ? 0.55F : 0.20F;
        spectrumDb_[band].store(previous + (db - previous) * coefficient,
                                std::memory_order_relaxed);
    }
}

}  // namespace iem
