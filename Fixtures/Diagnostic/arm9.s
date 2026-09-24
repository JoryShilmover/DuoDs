/* Duo DS authored diagnostic. SPDX-License-Identifier: MIT
 * Bare-metal DS homebrew: independently authored, no SDK, BIOS or logo assets.
 * Animated native bitmaps; hold A/B/D-pad to change the upper screen color.
 */
.syntax unified
.arm
.global _start
_start:
    ldr r0, =0x04000304
    ldr r1, =0x820f
    strh r1, [r0]
    ldr r0, =0x04000240
    mov r1, #0x81
    strb r1, [r0]
    mov r1, #0x84
    strb r1, [r0, #2]
    ldr r0, =0x04000000
    ldr r1, =0x00010405
    str r1, [r0]
    ldr r2, =0x04001000
    str r1, [r2]
    ldr r1, =0x4080
    strh r1, [r0, #12]
    strh r1, [r2, #12]
    mov r1, #256
    strh r1, [r0, #0x20]
    strh r1, [r0, #0x26]
    strh r1, [r2, #0x20]
    strh r1, [r2, #0x26]
    mov r8, #0
frame:
    ldr r0, =0x04000006
wait_visible:
    ldrh r1, [r0]
    cmp r1, #192
    bge wait_visible
wait_vblank:
    ldrh r1, [r0]
    cmp r1, #192
    blt wait_vblank
    add r8, r8, #1
    ldr r0, =0x04000130
    ldrh r7, [r0]
    mvn r7, r7
    and r7, r7, #255
    ldr r0, =0x06000000
    ldr r1, =0x06200000
    mov r2, #0
    ldr r6, =49152
pixel:
    add r3, r2, r8
    and r3, r3, #31
    orr r3, r3, #0x8000
    eor r3, r3, r7, lsl #5
    strh r3, [r0], #2
    mov r4, r2, lsr #8
    add r4, r4, r8, lsr #1
    and r4, r4, #31
    orr r4, r4, #0x8000
    orr r4, r4, #0x3e0
    strh r4, [r1], #2
    add r2, r2, #1
    cmp r2, r6
    blt pixel
    b frame
.ltorg
