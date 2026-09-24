#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

// Exactly one producer (retro_run) and one audio render consumer. Indices are
// monotonic; producer never overwrites unread samples. The callback allocates
// nothing and touches no mutex.
class SPSCAudioRing {
public:
    static constexpr size_t capacity = 32768;

    size_t push(const int16_t* stereo, size_t frames) noexcept {
        const uint64_t write = write_.load(std::memory_order_relaxed);
        const uint64_t read = read_.load(std::memory_order_acquire);
        const size_t available = capacity - static_cast<size_t>(write - read);
        const size_t accepted = std::min(frames, available);
        for (size_t i = 0; i < accepted; ++i) {
            const size_t offset = ((write + i) % capacity) * 2;
            samples_[offset] = static_cast<float>(stereo[i * 2]) / 32768.0f;
            samples_[offset + 1] = static_cast<float>(stereo[i * 2 + 1]) / 32768.0f;
        }
        write_.store(write + accepted, std::memory_order_release);
        if (accepted < frames) overruns_.fetch_add(1, std::memory_order_relaxed);
        produced_.fetch_add(accepted, std::memory_order_relaxed);
        return accepted;
    }

    // Returns the number of real frames. The full destination is always
    // initialized, including underrun silence.
    size_t pop(float* stereo, size_t frames) noexcept {
        if (!stereo) return 0;
        const uint64_t read = read_.load(std::memory_order_relaxed);
        const uint64_t write = write_.load(std::memory_order_acquire);
        const size_t accepted = std::min(frames, static_cast<size_t>(write - read));
        for (size_t i = 0; i < accepted; ++i) {
            const size_t offset = ((read + i) % capacity) * 2;
            stereo[i * 2] = samples_[offset];
            stereo[i * 2 + 1] = samples_[offset + 1];
        }
        std::fill(stereo + accepted * 2, stereo + frames * 2, 0.0f);
        read_.store(read + accepted, std::memory_order_release);
        consumed_.fetch_add(accepted, std::memory_order_relaxed);
        if (accepted < frames) underruns_.fetch_add(1, std::memory_order_relaxed);
        return accepted;
    }

    // Caller first quiesces the consumer; this is an executor-only operation.
    void clear() noexcept {
        read_.store(write_.load(std::memory_order_acquire), std::memory_order_release);
    }

    uint64_t produced() const noexcept { return produced_.load(std::memory_order_relaxed); }
    uint64_t consumed() const noexcept { return consumed_.load(std::memory_order_relaxed); }
    uint64_t underruns() const noexcept { return underruns_.load(std::memory_order_relaxed); }
    uint64_t overruns() const noexcept { return overruns_.load(std::memory_order_relaxed); }

private:
    std::array<float, capacity * 2> samples_{};
    std::atomic<uint64_t> write_{0}, read_{0};
    std::atomic<uint64_t> produced_{0}, consumed_{0}, underruns_{0}, overruns_{0};
};
