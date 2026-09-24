#include "include/DuoCore.h"
#include "../Audio/SPSCAudioRing.hpp"

#include <libretro.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <new>
#include <string>
#include <vector>

namespace {
constexpr size_t kWidth = 256, kHeight = 384, kFrameBytes = kWidth * kHeight * 4;
constexpr unsigned kLidModifier = 12; // L2, followed by Y (libretro ID 1).
constexpr const char* kOptions[][2] = {
    {"melonds_jit_enable", "disabled"},
    {"melonds_render_mode", "software"},
    {"melonds_screen_layout1", "top-bottom"},
    {"melonds_number_of_screen_layouts", "1"},
    {"melonds_screen_gap", "0"},
    {"melonds_secondary_screen_scale", "100"},
    {"melonds_touch_mode", "touch"},
    {"melonds_show_cursor", "disabled"},
    {"melonds_threaded_renderer", "disabled"},
    {"melonds_mic_input", "silence"}, // capture requires a separate permission/capture path
};

std::atomic<DuoCore*> g_active{nullptr};
}

struct DuoCore {
    std::string system_path, save_path, rom_path, error;
    SPSCAudioRing audio;
    std::vector<uint8_t> frame = std::vector<uint8_t>(kFrameBytes);
    DuoInput input{};
    double fps = 0, sample_rate = 0;
    uint64_t frames = 0, video_frames = 0;
    bool initialized = false, loaded = false, shutdown = false, lid_pulse = false;
    bool valid_video = false;
};

namespace {
DuoCore* current() noexcept { return g_active.load(std::memory_order_acquire); }

void log_cb(enum retro_log_level level, const char* format, ...) {
    DuoCore* c = current();
    if (!c || !format || level != RETRO_LOG_ERROR) return;
    // This core passes an already formatted string as the printf format, with
    // no arguments; copying it literally avoids interpreting stray '%' chars.
    if (std::strstr(format, "Error screen initialized")) {
        c->shutdown = true; // The core returned success but booted only its error UI.
    } else if (c->error.empty()) {
        c->error = format;
    }
}

bool environment_cb(unsigned command, void* data) {
    DuoCore* c = current();
    if (!c) return false;
    switch (command) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            if (!data) return false;
            *static_cast<const char**>(data) = c->system_path.c_str(); return true;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            if (!data) return false;
            *static_cast<const char**>(data) = c->save_path.c_str(); return true;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            return data && *static_cast<retro_pixel_format*>(data) == RETRO_PIXEL_FORMAT_XRGB8888;
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            if (!data) return false;
            *static_cast<unsigned*>(data) = 2; return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            if (!data) return false;
            auto* variable = static_cast<retro_variable*>(data);
            if (!variable->key) return false;
            for (const auto& option : kOptions) {
                if (std::strcmp(variable->key, option[0]) == 0) {
                    variable->value = option[1]; return true;
                }
            }
            variable->value = nullptr; return false;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            if (!data) return false;
            *static_cast<bool*>(data) = false; return true;
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            return true;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
            if (!data) return false;
            static_cast<retro_log_callback*>(data)->log = log_cb; return true;
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
            return true;
        case RETRO_ENVIRONMENT_SET_MESSAGE:
            if (data) c->error = static_cast<retro_message*>(data)->msg ?: "Core message";
            return true;
        case RETRO_ENVIRONMENT_SET_MESSAGE_EXT:
            if (data) {
                auto* message = static_cast<retro_message_ext*>(data);
                if (message->level == RETRO_LOG_ERROR && message->msg) c->error = message->msg;
            }
            return true;
        case RETRO_ENVIRONMENT_SHUTDOWN:
            c->shutdown = true;
            if (c->error.empty()) c->error = "Emulator core requested shutdown";
            return true;
        case RETRO_ENVIRONMENT_SET_ROTATION:
            return data && *static_cast<unsigned*>(data) == 0;
        default:
            return false;
    }
}

void video_cb(const void* data, unsigned width, unsigned height, size_t pitch) {
    DuoCore* c = current();
    if (!c || !data || width != kWidth || height != kHeight || pitch < kWidth * 4) return;
    const auto* source = static_cast<const uint8_t*>(data);
    for (size_t y = 0; y < kHeight; ++y) {
        auto* dest = c->frame.data() + y * kWidth * 4;
        std::memcpy(dest, source + y * pitch, kWidth * 4);
        // Libretro XRGB8888 is BGRA byte order on little endian, with undefined A.
        for (size_t x = 0; x < kWidth; ++x) dest[x * 4 + 3] = 0xff;
    }
    c->valid_video = true;
    ++c->video_frames;
}

void audio_sample_cb(int16_t left, int16_t right) {
    const int16_t sample[2] = {left, right};
    if (DuoCore* c = current()) c->audio.push(sample, 1);
}

size_t audio_batch_cb(const int16_t* data, size_t frames) {
    DuoCore* c = current();
    return c && data ? c->audio.push(data, frames) : 0;
}

void input_poll_cb() {}

int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    DuoCore* c = current();
    if (!c || port != 0 || index != 0) return 0;
    if (device == RETRO_DEVICE_JOYPAD) {
        uint16_t buttons = c->input.buttons;
        if (c->lid_pulse) buttons |= static_cast<uint16_t>((1u << kLidModifier) | (1u << RETRO_DEVICE_ID_JOYPAD_Y));
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return static_cast<int16_t>(buttons);
        return id < 16 && (buttons & (1u << id)) ? 1 : 0;
    }
    if (device == RETRO_DEVICE_POINTER) {
        if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return c->input.touching ? 1 : 0;
        // Source screen layout maps the full 256x384 buffer and subtracts the
        // lower-screen translation. Use pixel centers for exact DS coordinates.
        if (id == RETRO_DEVICE_ID_POINTER_X || id == RETRO_DEVICE_ID_POINTER_Y) {
            const unsigned pixel = id == RETRO_DEVICE_ID_POINTER_X
                ? std::min<unsigned>(c->input.touch_x, 255)
                : std::min<unsigned>(c->input.touch_y, 191) + 192;
            const unsigned extent = id == RETRO_DEVICE_ID_POINTER_X ? 256 : 384;
            const int value = static_cast<int>(std::lround((2.0 * (pixel + 0.5) / extent - 1.0) * 32767.0));
            return static_cast<int16_t>(std::clamp(value, -32767, 32767));
        }
    }
    return 0;
}
}

extern "C" {
DuoCore* duo_create(const char* system_path, const char* save_path) {
    if (!system_path || !save_path) return nullptr;
    DuoCore* c = new (std::nothrow) DuoCore;
    if (!c) return nullptr;
    DuoCore* expected = nullptr;
    if (!g_active.compare_exchange_strong(expected, c, std::memory_order_acq_rel)) { delete c; return nullptr; }
    c->system_path = system_path;
    c->save_path = save_path;
    retro_set_environment(environment_cb);
    retro_set_video_refresh(video_cb);
    retro_set_audio_sample(audio_sample_cb);
    retro_set_audio_sample_batch(audio_batch_cb);
    retro_set_input_poll(input_poll_cb);
    retro_set_input_state(input_state_cb);
    retro_init();
    c->initialized = true;
    return c;
}

bool duo_load(DuoCore* c, const char* rom_path) {
    if (!c || c != current() || !c->initialized || c->loaded || !rom_path) return false;
    c->error.clear(); c->shutdown = false; c->rom_path = rom_path;
    retro_game_info info{};
    info.path = c->rom_path.c_str();
    const bool loaded = retro_load_game(&info);
    c->loaded = loaded;
    if (!loaded || c->shutdown) {
        if (c->error.empty()) c->error = "The core could not load this DS file";
        return false;
    }
    retro_system_av_info av{};
    retro_get_system_av_info(&av);
    c->fps = av.timing.fps;
    c->sample_rate = av.timing.sample_rate;
    if (!(c->fps > 0 && std::isfinite(c->fps) && c->sample_rate > 0 && std::isfinite(c->sample_rate))) {
        c->error = "Core reported an invalid frame or audio rate"; return false;
    }
    return true;
}

bool duo_run(DuoCore* c, DuoInput input) {
    if (!c || c != current() || !c->loaded || c->shutdown) return false;
    c->error.clear();
    c->input = input;
    retro_run();
    c->lid_pulse = false;
    ++c->frames;
    return !c->shutdown;
}

void duo_toggle_lid(DuoCore* c) { if (c && c == current()) c->lid_pulse = true; }

const uint8_t* duo_frame(DuoCore* c, size_t* byte_count, uint64_t* sequence) {
    if (byte_count) *byte_count = c && c->valid_video ? kFrameBytes : 0;
    if (sequence) *sequence = c ? c->video_frames : 0;
    return c && c->valid_video ? c->frame.data() : nullptr;
}

size_t duo_read_audio(DuoCore* c, float* stereo, size_t frames) {
    if (!stereo) return 0;
    if (!c || c != current()) {
        std::fill(stereo, stereo + frames * 2, 0.0f);
        return 0;
    }
    return c->audio.pop(stereo, frames);
}
void duo_clear_audio(DuoCore* c) { if (c) c->audio.clear(); }
void duo_stats(DuoCore* c, DuoStats* stats) {
    if (!stats) return;
    *stats = {};
    if (!c) return;
    stats->fps = c->fps; stats->sample_rate = c->sample_rate;
    stats->frames = c->frames; stats->video_frames = c->video_frames;
    stats->audio_produced = c->audio.produced(); stats->audio_consumed = c->audio.consumed();
    stats->audio_underruns = c->audio.underruns(); stats->audio_overruns = c->audio.overruns();
}
size_t duo_save_size(DuoCore* c) { return c && c->loaded ? retro_get_memory_size(RETRO_MEMORY_SAVE_RAM) : 0; }
bool duo_copy_save(DuoCore* c, void* bytes, size_t size) {
    const size_t actual = duo_save_size(c);
    const void* source = c && c->loaded ? retro_get_memory_data(RETRO_MEMORY_SAVE_RAM) : nullptr;
    if (!source || !bytes || actual == 0 || size != actual) return false;
    std::memcpy(bytes, source, size); return true;
}
bool duo_restore_save(DuoCore* c, const void* bytes, size_t size) {
    const size_t actual = duo_save_size(c);
    void* dest = c && c->loaded ? retro_get_memory_data(RETRO_MEMORY_SAVE_RAM) : nullptr;
    if (!dest || !bytes || actual == 0 || size != actual) return false;
    std::memcpy(dest, bytes, size); return true;
}
size_t duo_state_size(DuoCore* c) { return c && c->loaded ? retro_serialize_size() : 0; }
bool duo_serialize(DuoCore* c, void* bytes, size_t size) {
    return c && c->loaded && bytes && size == duo_state_size(c) && size > 0 && retro_serialize(bytes, size);
}
bool duo_unserialize(DuoCore* c, const void* bytes, size_t size) {
    return c && c->loaded && bytes && size == duo_state_size(c) && size > 0 && retro_unserialize(bytes, size);
}
const char* duo_error(DuoCore* c) { return c ? c->error.c_str() : "Core instance unavailable"; }
void duo_destroy(DuoCore* c) {
    if (!c || c != current()) return;
    if (c->loaded) retro_unload_game();
    if (c->initialized) retro_deinit();
    g_active.store(nullptr, std::memory_order_release);
    delete c;
}
}
