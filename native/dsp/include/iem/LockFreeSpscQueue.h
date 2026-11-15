#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <type_traits>

namespace iem {

// Single-producer/single-consumer queue. One slot is reserved to distinguish full
// from empty, so usable capacity is Capacity - 1. The producer and consumer must
// each be serialized to one thread.
template <typename T, std::size_t Capacity>
#if defined(_MSC_VER)
// The two indices intentionally occupy separate cache lines. MSVC reports the
// resulting tail padding as C4324; keep that expected warning local to this
// cache-aligned real-time queue instead of weakening /WX for the whole runner.
#pragma warning(push)
#pragma warning(disable : 4324)
#endif
class LockFreeSpscQueue final {
    static_assert(Capacity >= 2, "Capacity must be at least two");
    static_assert(std::is_trivially_copyable<T>::value,
                  "Queue values must be trivially copyable");
    static_assert(std::atomic<std::size_t>::is_always_lock_free,
                  "Real-time queue indices must be lock-free on this target");

public:
    bool TryPush(const T& value) noexcept {
        const auto write = writeIndex_.load(std::memory_order_relaxed);
        const auto next = Increment(write);
        if (next == readIndex_.load(std::memory_order_acquire)) {
            return false;
        }
        values_[write] = value;
        writeIndex_.store(next, std::memory_order_release);
        return true;
    }

    bool TryPop(T& value) noexcept {
        const auto read = readIndex_.load(std::memory_order_relaxed);
        if (read == writeIndex_.load(std::memory_order_acquire)) {
            return false;
        }
        value = values_[read];
        readIndex_.store(Increment(read), std::memory_order_release);
        return true;
    }

private:
    static constexpr std::size_t Increment(std::size_t index) noexcept {
        return (index + 1U) % Capacity;
    }

    std::array<T, Capacity> values_{};
    alignas(64) std::atomic<std::size_t> writeIndex_{0};
    alignas(64) std::atomic<std::size_t> readIndex_{0};
};
#if defined(_MSC_VER)
#pragma warning(pop)
#endif

}  // namespace iem
