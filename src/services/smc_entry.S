/* Copyright (C) 2018  Nexell Co., Ltd.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *  * Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *  * Neither the name of the Nexell nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ''AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL,SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#include "../include/asm.h"
#include "../include/armv7.h"
#include "../include/nxp3220.h"

.global get_smc_addr
.global sip_smc_handler

.global iram_dev_freq
iram_dev_freq:
	b	.

.global iram_suspend
iram_suspend:
//	b	psci_cpu_suspend_start
	b	.

/* monitor mode - fiq handler */
ENTRY(smc_asm_monitor_fiq_handler)
	stmfd	sp!, {r0-r7, lr}
//	bl	smc_monitor_fiq_handler
	ldmfd	sp!, {r0-r7, lr}
	subs	pc, r14, #4
ENDPROC(smc_asm_monitor_fiq_handler)

/*
 * SMC Caller Handler
 */
EXPORT(sip_smc_handler)
ENTRY(smc_asm_handler)
	stmfd	sp!, {r4-r12, lr}
	/*
	 * store the parameters in the stack
	 * before switching to secure mode.
	 */
	stmfd	sp!, {r0-r3}
	/* change the secure-mode */
	mrc	p15, 0, r9, c1, c1, 0
	bic	r9, r9, #(1 << 0)
	mcr	p15, 0, r9, c1, c1, 0

	/* load the parameters in the stack */
	ldmfd	sp!, {r0-r3}
	bl	sip_smc_handler

	/* change the non-secure-mode */
	mrc	p15, 0, r9, c1, c1, 0
	orr	r9, r9, #(1 << 0)
	mcr	p15, 0, r9, c1, c1, 0

	ldmfd	sp!, {r4-r12, lr}
	movs	pc, r14
ENDPROC(smc_asm_handler)

/*
 * Monitor Mode - Exception Vetor table
 *
 */
.align 6
.global monitor_vectors
monitor_vectors:
        b       iram_suspend							/* 00 - reset will never get here	*/
        b       .    								/* 04 -					*/
        b       smc_asm_handler							/* 08 - SMC Interrupt			*/
        b       .          							/* 0C -					*/
        b       .          							/* 10 -					*/
        b       iram_dev_freq							/* 14 -	No Exception get here		*/
        b       .                   						/* 18 -					*/
//	b       smc_asm_monitor_fiq_handler					/* 1C - FIQ Interrupt			*/

/*
 *  Only Monitor Mode - Deoks
 */
.align 4
ENTRY(monitor_mode_init)
	/* -----------------------------------------
	 * Secure - SVC Mode -> Monitor Mode
	 * Changes in the SVC Mode to MON Mode,
	 * and store the link register values.
	 * -----------------------------------------
	 */
	mov	r8, lr
	mov	lr, #0								// svc lr
	mov	sp, #0								// svc sp
	/* Switch to monitor mode  */
	msr	CPSR_c,  #(MODE_MON|I_BIT|F_BIT)

        mrc     p15, 0, r0, c1, c0, 0						// Read CP15 System Control register
        bic     r0, r0, #(BIT1_V|BIT1_I|BIT1_Z) 				// Clear V:13, I:12, Z:11 bit to disable High Vector, I-Cache, Branch Prediction
        bic     r0, r0, #(BIT1_C|BIT1_M)					// Clear C:2, M:0 bit to disable D Cache, MMU
        mcr     p15, 0, r0, c1, c0, 0						// Write value back to CP15 System Control register

	/* Stack size set to monitor mode  */
	ldr     sp, =BL32_BASEADDR
	add     sp, sp, #BL32_SIZE
	sub	sp, sp, #SVC_STACK_SIZE
	sub	sp, sp, #MON_STACK_SIZE

	mrc     p15, 0, r12, c0, c0, 5						// Get our cpu id
	ands    r12, r12, #0xF							// Save CPU id

	mov     r1, #0x100
	sub     r2, r12, #1
	and     r2, r2, #3
	mul     r1, r1, r2
	sub     sp, sp, r1

	/* (MVBAR) set to monitor vector base address */
	ldr	r0, =monitor_vectors
	mcr	p15, 0, r0, c12, c0, 1

	/* return */
	bx	r8
ENDPROC(monitor_mode_init)

ENTRY(set_montior_vector)
	/* (MVBAR) set to monitor vector base address */
	ldr	r0, =monitor_vectors
	mcr	p15, 0, r0, c12, c0, 1
	bx	lr
ENDPROC(set_montior_vector)

ENTRY(smc_call)
	smc	0
	bx	lr
ENDPROC(smc_call)
