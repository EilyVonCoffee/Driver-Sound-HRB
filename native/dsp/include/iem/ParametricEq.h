#pragma once

#include "iem/LockFreeSpscQueue.h"

#include <array>
#include <cstddef>

namespace iem {

constexpr std::size_t kEqBandCount = 10;

enum class FilterType : unsigned char {
    LowPass,
    HighPass,
    LowShelf,
    HighShelf,
    Peaking,
};

struct BandParameters {
    bool enabled{false};
    FilterType type{FilterType::Peaking};
    float frequencyHz{1000.0F};
    float gainDb{0.0F};
    float q{0.707F};
};

struct EqConfiguration {
    bool enabled{true};
    float preampDb{0.0F};
    std::array<BandParameters, kEqBandCount> bands{};
};

struct BiquadCoefficients {
    float b0{1.0F};
    float b1{0.0F};
    float b2{0.0F};
    float a1{0.0F};
    float a2{0.0F};
};

struct PreparedBand {
    bool enabled{false};
    BiquadCoefficients coefficients{};
};

struct PreparedConfiguration {
    bool enabled{true};
    float preampLinear{1.0F};
    std::size_t transitionFrames{960};
    std::array<PreparedBand, kEqBandCount> bands{};
};

// Call Submit() from one serialized control thread. Process() is audio-thread safe
// and does no allocation, locking, or coefficient design.
class ParametricEq final {
public:
    bool Submit(const EqConfiguration& configuration, float sampleRate) noexcept;

    // Interleaved float PCM. Mono and stereo are processed; other channel counts
    // pass through unchanged. input and output may point to the same buffer.
    void Process(const float* input,
                 float* output,
                 std::size_t frames,
                 std::size_t channels) noexcept;

private:
    struct FilterState {
        double z1[2]{0.0, 0.0};
        double z2[2]{0.0, 0.0};
    };

    struct FilterInstance {
        BiquadCoefficients coefficients{};
        FilterState state{};
    };

    struct FilterBank {
        bool enabled{true};
        float preampLinear{1.0F};
        std::array<FilterInstance, kEqBandCount> filters{};
    };

    static PreparedBand PrepareBand(const BandParameters& band,
                                    float sampleRate) noexcept;
    void BeginNextTransition() noexcept;
    float ProcessBank(FilterBank& bank, float input, std::size_t channel) noexcept;

    LockFreeSpscQueue<PreparedConfiguration, 8> updates_{};
    std::array<FilterBank, 2> banks_{};
    std::size_t activeBank_{0};
    std::size_t pendingBank_{1};
    std::size_t transitionFrames_{960};
    std::size_t transitionRemaining_{0};
};

}  // namespace iem
