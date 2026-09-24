// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
#include "../../Emulator/CoreBridge/include/DuoCore.h"
#include "../../Emulator/Audio/SPSCAudioRing.hpp"

#include <libretro.h>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <unistd.h>

namespace {
retro_environment_t env = nullptr;
retro_video_refresh_t video = nullptr;
retro_audio_sample_batch_t audio = nullptr;
retro_input_state_t input = nullptr;
int init_count = 0, deinit_count = 0, unload_count = 0;
int16_t last_pointer_x = 0, last_pointer_y = 0;
uint16_t last_buttons = 0;
uint8_t save_ram[4] = {1, 2, 3, 4};
uint8_t state[8] = {9, 8, 7, 6, 5, 4, 3, 2};
}

extern "C" {
void retro_set_environment(retro_environment_t callback) { env = callback; }
void retro_set_video_refresh(retro_video_refresh_t callback) { video = callback; }
void retro_set_audio_sample(retro_audio_sample_t) {}
void retro_set_audio_sample_batch(retro_audio_sample_batch_t callback) { audio = callback; }
void retro_set_input_poll(retro_input_poll_t) {}
void retro_set_input_state(retro_input_state_t callback) { input = callback; }
void retro_init(void) { ++init_count; }
void retro_deinit(void) { ++deinit_count; }
bool retro_load_game(const retro_game_info* info) {
    assert(info && info->path && env);
    // Core declares need_fullpath=false: host must supply the ROM bytes.
    assert(info->data && info->size == 4 && std::memcmp(info->data, "NDS!", 4) == 0);
    const char* system = nullptr;
    assert(env(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY, &system));
    assert(std::strcmp(system, "/system") == 0);
    retro_variable variable{"melonds_screen_gap", nullptr};
    assert(env(RETRO_ENVIRONMENT_GET_VARIABLE, &variable));
    assert(std::strcmp(variable.value, "0") == 0);
    variable = {"melonds_jit_enable", nullptr};
    assert(env(RETRO_ENVIRONMENT_GET_VARIABLE, &variable));
    assert(std::strcmp(variable.value, "disabled") == 0);
    // Host overrides win over the built-in table; the nickname answers the username request.
    variable = {"melonds_threaded_renderer", nullptr};
    assert(env(RETRO_ENVIRONMENT_GET_VARIABLE, &variable) && std::strcmp(variable.value, "enabled") == 0);
    variable = {"melonds_firmware_language", nullptr};
    assert(env(RETRO_ENVIRONMENT_GET_VARIABLE, &variable) && std::strcmp(variable.value, "fr") == 0);
    const char* username = nullptr;
    assert(env(RETRO_ENVIRONMENT_GET_USERNAME, &username) && std::strcmp(username, "Jory") == 0);
    retro_pixel_format format = RETRO_PIXEL_FORMAT_XRGB8888;
    assert(env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &format));
    return true;
}
void retro_unload_game(void) { ++unload_count; }
void retro_get_system_av_info(retro_system_av_info* info) {
    info->timing.fps = 59.8261;
    info->timing.sample_rate = 32768;
}
void retro_run(void) {
    last_buttons = static_cast<uint16_t>(input(0, RETRO_DEVICE_JOYPAD, 0, RETRO_DEVICE_ID_JOYPAD_MASK));
    last_pointer_x = input(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_X);
    last_pointer_y = input(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_Y);
    assert(input(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_PRESSED));
    static std::vector<uint32_t> pixels(256 * 384, 0x00112233);
    video(pixels.data(), 256, 384, 256 * 4);
    const int16_t samples[] = {32767, -32768, 0, 0};
    assert(audio(samples, 2) == 2);
}
size_t retro_get_memory_size(unsigned type) { return type == RETRO_MEMORY_SAVE_RAM ? sizeof(save_ram) : 0; }
void* retro_get_memory_data(unsigned type) { return type == RETRO_MEMORY_SAVE_RAM ? save_ram : nullptr; }
size_t retro_serialize_size(void) { return sizeof(state); }
bool retro_serialize(void* bytes, size_t size) {
    if (size != sizeof(state)) return false;
    std::memcpy(bytes, state, size); return true;
}
bool retro_unserialize(const void* bytes, size_t size) {
    if (size != sizeof(state)) return false;
    std::memcpy(state, bytes, size); return true;
}
}

int main() {
    SPSCAudioRing ring;
    float output[8]{};
    assert(ring.pop(output, 4) == 0);
    assert(ring.underruns() == 1);
    const int16_t sample[4] = {32767, -32768, 0, 16384};
    assert(ring.push(sample, 2) == 2);
    assert(ring.pop(output, 4) == 2);
    assert(output[0] > 0.99f && output[1] == -1.0f && output[3] == 0.5f);
    assert(output[4] == 0 && output[7] == 0);
    std::vector<int16_t> huge((SPSCAudioRing::capacity + 1) * 2);
    assert(ring.push(huge.data(), SPSCAudioRing::capacity + 1) == SPSCAudioRing::capacity);
    assert(ring.overruns() == 1);

    // Priming: silence without consuming until the cushion exists; re-prime after running dry.
    SPSCAudioRing primed;
    primed.set_prime(4);
    const int16_t two[4] = {1000, 1000, 1000, 1000};
    float out[8];
    assert(primed.push(two, 2) == 2);
    assert(primed.pop(out, 2) == 0 && out[0] == 0.0f && primed.underruns() == 0 && primed.buffered() == 2);
    assert(primed.push(two, 2) == 2);
    assert(primed.pop(out, 4) == 4 && out[0] > 0.0f && primed.buffered() == 0);
    assert(primed.pop(out, 1) == 0 && primed.underruns() == 1);      // ran dry: counted once
    assert(primed.push(two, 2) == 2 && primed.pop(out, 2) == 0);    // then re-primes instead of stuttering
    primed.clear();
    assert(primed.buffered() == 0);

    DuoCore* core = duo_create("/system", "/save");
    assert(core && !duo_create("/system", "/save"));
    assert(!duo_load(core, "/nonexistent/rom.nds"));
    assert(duo_set_option(core, "melonds_threaded_renderer", "enabled"));
    assert(duo_set_option(core, "melonds_firmware_language", "fr"));
    duo_set_username(core, "Jory");
    char rom[] = "/tmp/duo-core-test-XXXXXX";
    const int fd = mkstemp(rom);
    assert(fd >= 0 && write(fd, "NDS!", 4) == 4 && close(fd) == 0);
    assert(duo_load(core, rom));
    // Microphone: the core obtains the host mic interface; reads are silence-padded and only while active.
    retro_microphone_interface mic{};
    mic.interface_version = RETRO_MICROPHONE_INTERFACE_VERSION;
    assert(env(RETRO_ENVIRONMENT_GET_MICROPHONE_INTERFACE, &mic));
    retro_microphone_t* handle = mic.open_mic(nullptr);
    int16_t heard[4] = {1, 1, 1, 1};
    assert(handle && mic.read_mic(handle, heard, 4) == -1 && !mic.get_mic_state(handle));
    assert(mic.set_mic_state(handle, true) && mic.get_mic_state(handle));
    const int16_t spoken[2] = {100, -200};
    duo_push_mic(core, spoken, 2);
    assert(mic.read_mic(handle, heard, 4) == 4 && heard[0] == 100 && heard[1] == -200 && heard[2] == 0 && heard[3] == 0);
    retro_microphone_params_t params{};
    assert(mic.get_params(handle, &params) && params.rate == 44100);
    mic.close_mic(handle);
    assert(!mic.get_mic_state(handle));
    std::remove(rom);
    DuoStats stats{};
    duo_stats(core, &stats);
    assert(std::abs(stats.fps - 59.8261) < 0.0001 && stats.sample_rate == 32768);
    DuoInput controls{};
    controls.buttons = 1u << RETRO_DEVICE_ID_JOYPAD_A;
    controls.touching = true;
    controls.touch_x = 255;
    controls.touch_y = 191;
    duo_toggle_lid(core);
    duo_toggle_lid(core); // two quick toggles must stay two pulses, separated by a release frame
    assert(duo_run(core, controls));
    assert(last_buttons & (1u << RETRO_DEVICE_ID_JOYPAD_A));
    assert(last_buttons & (1u << RETRO_DEVICE_ID_JOYPAD_L2));
    assert(last_buttons & (1u << RETRO_DEVICE_ID_JOYPAD_Y));
    assert(last_pointer_x > 32000 && last_pointer_y > 32000);
    assert(duo_run(core, controls));
    assert(!(last_buttons & (1u << RETRO_DEVICE_ID_JOYPAD_L2)));
    assert(duo_run(core, controls));
    assert(last_buttons & (1u << RETRO_DEVICE_ID_JOYPAD_L2));
    assert(duo_run(core, controls));
    assert(!(last_buttons & (1u << RETRO_DEVICE_ID_JOYPAD_L2)));
    controls.touch_x = 0;
    controls.touch_y = 0;
    assert(duo_run(core, controls));
    assert(last_pointer_x < -32000);
    assert(std::abs(last_pointer_y) < 100); // y=192 is the lower screen's first row.
    size_t frame_size = 0; uint64_t frame_id = 0;
    const uint8_t* frame = duo_frame(core, &frame_size, &frame_id);
    assert(frame && frame_size == 256 * 384 * 4 && frame_id == 5); // 3 input runs + 2 lid-queue runs (checked before the muted run below)
    assert(frame[0] == 0x33 && frame[1] == 0x22 && frame[2] == 0x11 && frame[3] == 0xff);
    assert(frame[frame_size - 1] == 0xff);
    float native_audio[8]{};
    // Load sets a ~60 ms prime (1966 frames at 32768 Hz); a few test frames stay queued as silence.
    const size_t queued = duo_audio_buffered(core);
    assert(queued > 0 && queued < 1966);
    assert(duo_read_audio(core, native_audio, 4) == 0 && native_audio[0] == 0.0f);
    assert(duo_audio_buffered(core) == queued);
    // Fast-forward drops muted frames' audio without counting overruns.
    duo_stats(core, &stats);
    const uint64_t overruns = stats.audio_overruns;
    duo_set_audio_muted(core, true);
    assert(duo_run(core, controls) && duo_audio_buffered(core) == queued);
    duo_set_audio_muted(core, false);
    duo_stats(core, &stats);
    assert(stats.audio_overruns == overruns);
    assert(!duo_set_option(core, "melonds_threaded_renderer", "disabled")); // only before load
    assert(duo_save_size(core) == 4);
    uint8_t copied[4]{};
    assert(!duo_copy_save(core, copied, 3));
    assert(duo_copy_save(core, copied, 4));
    assert(copied[0] == 1 && copied[3] == 4);
    const uint8_t restored[4] = {5, 6, 7, 8};
    assert(duo_restore_save(core, restored, 4));
    assert(save_ram[0] == 5 && save_ram[3] == 8);
    uint8_t snapshot[8]{};
    assert(duo_serialize(core, snapshot, 8));
    std::memset(state, 0, 8);
    assert(duo_unserialize(core, snapshot, 8) && state[0] == 9);
    duo_destroy(core);
    assert(init_count == 1 && deinit_count == 1 && unload_count == 1);
    // Callback pointers may remain in the static core; no instance is accessed.
    video(snapshot, 256, 384, 256 * 4);
    DuoCore* second = duo_create("/system", "/save");
    assert(second); duo_destroy(second);
    assert(init_count == 2 && deinit_count == 2);
}
