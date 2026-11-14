#include "iem/ParametricEq.h"

#include <algorithm>
#include <cmath>

namespace iem {
namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kMinFrequencyHz = 20.0;
constexpr double kMaxFrequencyHz = 20000.0;

double FiniteOr(double value, double fallback) noexcept {
    return std::isfinite(value) ? value : fallback;
}

BiquadCoefficients Normalize(double b0,
                             double b1,
                             double b2,
                             double a0,
                             double a1,
                             double a2) noexcept {
    if (!std::isfinite(a0) || std::abs(a0) < 1.0e-12) {
        return {};
    }
    const auto inverseA0 = 1.0 / a0;
    return {
        static_cast<float>(b0 * inverseA0),
        static_cast<float>(b1 * inverseA0),
        static_cast<float>(b2 * inverseA0),
        static_cast<float>(a1 * inverseA0),
        static_cast<float>(a2 * inverseA0),
    };
}

}  // namespace

bool ParametricEq::Submit(const EqConfiguration& configuration,
                          float sampleRate) noexcept {
    if (!std::isfinite(sampleRate) || sampleRate < 8000.0F || sampleRate > 384000.0F) {
        return false;
    }

    PreparedConfiguration prepared{};
    prepared.enabled = configuration.enabled;
    const auto preampDb = std::clamp(FiniteOr(configuration.preampDb, 0.0), -24.0, 12.0);
    prepared.preampLinear = static_cast<float>(std::pow(10.0, preampDb / 20.0));

    for (std::size_t i = 0; i < kEqBandCount; ++i) {
        prepared.bands[i] = PrepareBand(configuration.bands[i], sampleRate);
    }

    prepared.transitionFrames = static_cast<std::size_t>(
        std::max(1.0, std::round(sampleRate * 0.020)));
    return updates_.TryPush(prepared);
}

PreparedBand ParametricEq::PrepareBand(const BandParameters& band,
                                       float sampleRate) noexcept {
    PreparedBand result{};
    result.enabled = band.enabled;
    if (!band.enabled) {
        return result;
    }

    const double nyquistSafeMax = std::max(kMinFrequencyHz,
                                           std::min(kMaxFrequencyHz,
                                                    static_cast<double>(sampleRate) * 0.49));
    const auto frequency = std::clamp(FiniteOr(band.frequencyHz, 1000.0),
                                      kMinFrequencyHz,
                                      nyquistSafeMax);
    const auto gainDb = std::clamp(FiniteOr(band.gainDb, 0.0), -24.0, 12.0);
    const auto q = std::clamp(FiniteOr(band.q, 0.707), 0.1, 10.0);
    const auto omega = 2.0 * kPi * frequency / static_cast<double>(sampleRate);
    const auto cosine = std::cos(omega);
    const auto sine = std::sin(omega);
    const auto a = std::pow(10.0, gainDb / 40.0);
    const auto alpha = sine / (2.0 * q);

    switch (band.type) {
        case FilterType::LowPass:
            result.coefficients = Normalize((1.0 - cosine) / 2.0,
                                            1.0 - cosine,
                                            (1.0 - cosine) / 2.0,
                                            1.0 + alpha,
                                            -2.0 * cosine,
                                            1.0 - alpha);
            break;
        case FilterType::HighPass:
            result.coefficients = Normalize((1.0 + cosine) / 2.0,
                                            -(1.0 + cosine),
                                            (1.0 + cosine) / 2.0,
                                            1.0 + alpha,
                                            -2.0 * cosine,
                                            1.0 - alpha);
            break;
        case FilterType::Peaking:
            result.coefficients = Normalize(1.0 + alpha * a,
                                            -2.0 * cosine,
                                            1.0 - alpha * a,
                                            1.0 + alpha / a,
                                            -2.0 * cosine,
                                            1.0 - alpha / a);
            break;
        case FilterType::LowShelf:
        case FilterType::HighShelf: {
            // RBJ shelf slope S is stable in [0.1, 1.0]. For these types q is
            // interpreted as S rather than resonant Q.
            const auto slope = std::clamp(q, 0.1, 1.0);
            const auto shelfAlpha = sine / 2.0 * std::sqrt(
                std::max(0.0, (a + 1.0 / a) * (1.0 / slope - 1.0) + 2.0));
            const auto twoSqrtAAlpha = 2.0 * std::sqrt(a) * shelfAlpha;
            if (band.type == FilterType::LowShelf) {
                result.coefficients = Normalize(
                    a * ((a + 1.0) - (a - 1.0) * cosine + twoSqrtAAlpha),
                    2.0 * a * ((a - 1.0) - (a + 1.0) * cosine),
                    a * ((a + 1.0) - (a - 1.0) * cosine - twoSqrtAAlpha),
                    (a + 1.0) + (a - 1.0) * cosine + twoSqrtAAlpha,
                    -2.0 * ((a - 1.0) + (a + 1.0) * cosine),
                    (a + 1.0) + (a - 1.0) * cosine - twoSqrtAAlpha);
            } else {
                result.coefficients = Normalize(
                    a * ((a + 1.0) + (a - 1.0) * cosine + twoSqrtAAlpha),
                    -2.0 * a * ((a - 1.0) + (a + 1.0) * cosine),
                    a * ((a + 1.0) + (a - 1.0) * cosine - twoSqrtAAlpha),
                    (a + 1.0) - (a - 1.0) * cosine + twoSqrtAAlpha,
                    2.0 * ((a - 1.0) - (a + 1.0) * cosine),
                    (a + 1.0) - (a - 1.0) * cosine - twoSqrtAAlpha);
            }
            break;
        }
    }
    return result;
}

void ParametricEq::BeginNextTransition() noexcept {
    PreparedConfiguration latest{};
    PreparedConfiguration next{};
    bool hasUpdate = false;
    // The queue has a fixed capacity; the fixed bound keeps callback work finite
    // even if the producer is submitting updates continuously.
    for (std::size_t i = 0; i < 8; ++i) {
        if (!updates_.TryPop(next)) {
            break;
        }
        latest = next;
        hasUpdate = true;
    }
    if (!hasUpdate) {
        return;
    }

    transitionFrames_ = std::max<std::size_t>(latest.transitionFrames, 1U);
    pendingBank_ = 1U - activeBank_;
    auto& destination = banks_[pendingBank_];
    const auto& source = banks_[activeBank_];
    destination.enabled = latest.enabled;
    destination.preampLinear = latest.preampLinear;
    for (std::size_t band = 0; band < kEqBandCount; ++band) {
        destination.filters[band].state = source.filters[band].state;
        destination.filters[band].coefficients = latest.bands[band].enabled
            ? latest.bands[band].coefficients
            : BiquadCoefficients{};
    }
    transitionRemaining_ = transitionFrames_;
}

float ParametricEq::ProcessBank(FilterBank& bank,
                                float input,
                                std::size_t channel) noexcept {
    auto sample = static_cast<double>(input) * bank.preampLinear;
    for (auto& filter : bank.filters) {
        const auto& c = filter.coefficients;
        const auto output = c.b0 * sample + filter.state.z1[channel];
        filter.state.z1[channel] = c.b1 * sample - c.a1 * output + filter.state.z2[channel];
        filter.state.z2[channel] = c.b2 * sample - c.a2 * output;
        sample = output;
    }
    return bank.enabled ? static_cast<float>(sample) : input;
}

void ParametricEq::Process(const float* input,
                           float* output,
                           std::size_t frames,
                           std::size_t channels) noexcept {
    if (input == nullptr || output == nullptr || channels == 0U) {
        return;
    }
    if (channels > 2U) {
        if (input != output) {
            std::copy(input, input + frames * channels, output);
        }
        return;
    }

    for (std::size_t frame = 0; frame < frames; ++frame) {
        if (transitionRemaining_ == 0U) {
            BeginNextTransition();
        }
        const auto blend = transitionRemaining_ == 0U
            ? 0.0F
            : static_cast<float>(transitionFrames_ - transitionRemaining_) /
                  static_cast<float>(std::max<std::size_t>(1U, transitionFrames_ - 1U));

        for (std::size_t channel = 0; channel < channels; ++channel) {
            const auto index = frame * channels + channel;
            const auto sample = input[index];
            const auto oldValue = ProcessBank(banks_[activeBank_], sample, channel);
            if (transitionRemaining_ == 0U) {
                output[index] = oldValue;
            } else {
                const auto newValue = ProcessBank(banks_[pendingBank_], sample, channel);
                output[index] = oldValue + (newValue - oldValue) * blend;
            }
        }

        if (transitionRemaining_ > 0U) {
            --transitionRemaining_;
            if (transitionRemaining_ == 0U) {
                activeBank_ = pendingBank_;
            }
        }
    }
}

}  // namespace iem
