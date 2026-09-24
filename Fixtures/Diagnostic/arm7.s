/* SPDX-License-Identifier: MIT. Authored PSG diagnostic tone, no samples. */
.syntax unified
.arm
.global _start
_start:
    ldr r0, =0x04000304
    mov r1, #1
    strh r1, [r0]
    ldr r0, =0x04000500
    ldr r1, =0x807f
    strh r1, [r0]
    ldr r0, =0x04000480
    ldr r1, =0xf000
    strh r1, [r0, #8]
    ldr r1, =0xe3400030
    str r1, [r0]
idle:
    b idle
.ltorg
