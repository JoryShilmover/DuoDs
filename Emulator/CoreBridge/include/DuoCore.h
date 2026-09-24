// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
#ifndef DUO_CORE_H
#define DUO_CORE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct DuoCore DuoCore;
typedef struct { uint16_t buttons, touch_x, touch_y; bool touching; } DuoInput;
typedef struct { double fps, sample_rate; uint64_t frames, video_frames, audio_produced, audio_consumed, audio_underruns, audio_overruns, audio_buffered, mic_pushed, mic_consumed; } DuoStats;
/* All lifecycle/run/save calls on ONE serial executor. One live instance maximum.
   Frame bytes owned by core host, valid until next run; caller copies before returning.
   Audio consumer is single real-time consumer, no locks/allocations in read_audio.
   Error string valid until next operation. paths remain copied for core lifetime. */
DuoCore *duo_create(const char *system_path, const char *save_path);
bool duo_load(DuoCore *, const char *rom_path);
bool duo_run(DuoCore *, DuoInput);
void duo_toggle_lid(DuoCore *);
const uint8_t *duo_frame(DuoCore *, size_t *byte_count, uint64_t *sequence);
size_t duo_read_audio(DuoCore *, float *interleaved_stereo, size_t frames);
void duo_clear_audio(DuoCore *);
/* Frames queued for playback (for pacing). Playback primes to ~60 ms before starting. */
size_t duo_audio_buffered(DuoCore *);
/* Host microphone samples: mono int16 at 44100 Hz, from the capture thread (single producer). */
void duo_push_mic(DuoCore *, const int16_t *samples, size_t count);
/* Push the core's buffered file writes (homebrew SD-card image) to the OS. Executor-only. */
void duo_flush_storage(DuoCore *);
void duo_stats(DuoCore *, DuoStats *);
size_t duo_save_size(DuoCore *);
bool duo_copy_save(DuoCore *, void *, size_t);
bool duo_restore_save(DuoCore *, const void *, size_t);
size_t duo_state_size(DuoCore *);
bool duo_serialize(DuoCore *, void *, size_t);
bool duo_unserialize(DuoCore *, const void *, size_t);
const char *duo_error(DuoCore *);
void duo_destroy(DuoCore *);
#ifdef __cplusplus
}
#endif
#endif
