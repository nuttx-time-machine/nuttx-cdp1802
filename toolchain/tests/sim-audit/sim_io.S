; sim_io.S — Step 02 simulator-audit helpers (validation only, not NuttX code).
;
; sim1802 I/O controller (sim1802_io.erl / sim1802_io.hrl):
;   OUT 6 / INP 6 : argument/result buffer
;   OUT 7         : command
;
; Calling convention: mikpe NCRT ABI (docs/cdp1802/abi.md): args in R7, R8
; (a char arg is in the low byte), result in R7, return with SEP 5, X=2,
; M(SP) is a scratch byte.

	.text

; void sim_cmd(unsigned char cmd, unsigned char arg)
	.global	sim_cmd
sim_cmd:
	glo	8
	str	2
	out	6		; buffer := arg   (OUT increments R(X))
	dec	2
	glo	7
	str	2
	out	7		; execute command
	dec	2
	sep	5

; unsigned char sim_cmd_read(unsigned char cmd): issue cmd, return buffer
	.global	sim_cmd_read
sim_cmd_read:
	glo	7
	str	2
	out	7
	dec	2
	inp	6		; D := M(R(X)) := buffer
	plo	7
	ldi	0
	phi	7
	sep	5

; unsigned char ie_is_set(void): uses LSIE (CC), long skip if IE=1
	.global	ie_is_set
ie_is_set:
	ldi	0
	phi	7
	ldi	1
	lsie			; IE=1: skip the next 2 bytes (the LDI 0)
	ldi	0
	plo	7
	sep	5

; void idle(void): IDL — wait for interrupt (DMA would also wake it)
	.global	idle
idle:
	idl
	sep	5

; void irq_enable(void) / irq_disable(void): RET / DIS with an inline X,P byte.
; The byte after the instruction is read via R(X); with X=P=3 it is the next
; byte of code, and it restores X=2, P=3.
	.global	irq_enable
irq_enable:
	sex	3
	ret
	.byte	0x23		; X=2, P=3
	sep	5

	.global	irq_disable
irq_disable:
	sex	3
	dis
	.byte	0x23
	sep	5

; void isr_install(void): R1 := isr_entry, R0 := &isr_save+1.
; R0 is used as the ISR's private save pointer, so the ISR never stores
; through R2 (see docs/toolchain-issues/0001).
	.global	isr_install
isr_install:
	ldi	%hi(isr_entry)
	phi	1
	ldi	%lo(isr_entry)
	plo	1
	ldi	%hi(isr_save_top+1)
	phi	0
	ldi	%lo(isr_save_top+1)
	plo	0
	sep	5

; Interrupt service routine (Step 02 audit harness; it predates ADR 0006 and
; saves state through R0, which is fine in the simulator: it has no DMA).
; Entry: P=1, X=2, IE=0, T=(X,P) of the interrupted code.  Save area
; (R0-relative):
;   isr_save_top    : T
;   isr_save_top-1  : D
;   isr_save_top-2  : DF (bit 0)
;   isr_save_top-3  : the I/O argument buffer of the interrupted code, which
;                     may be between its OUT 6 and OUT 7
;   isr_save_top-4  : irq_count (low byte counter, also exported)
;   isr_save_top-5  : scratch for OUT/INP
;   isr_save_top-6  : irq_mask, IRQs re-enabled after each acknowledge
isr_exit:
	inc	0		; -> buffer slot
	out	6		; restore the I/O buffer, R0 -> DF slot
	ldxa			; D := saved DF byte, R0 -> D slot
	shr			; DF := bit 0
	ldxa			; D := saved D, R0 -> T slot
	ret			; X,P := T; R0++ ; IE := 1
isr_entry:			; R1 points here after RET above
	sex	0
	dec	0		; R0 -> T slot
	sav			; M(R0) := T
	dec	0
	stxd			; save D
	shlc			; D.0 := DF
	stxd			; save DF, R0 -> buffer slot
	inp	6		; save the I/O buffer
	dec	0		; R0 -> counter
	ldx
	adi	1
	str	0		; irq_count++
	dec	0		; R0 -> scratch
	ldi	0x10		; INTERRUPT_ACKNOWLEDGE
	str	0
	out	7
	dec	0
	inp	6		; D := IRQ number (ignored)
	dec	0		; -> irq_mask
	ldx			; D := irq_mask
	inc	0		; -> scratch
	str	0
	out	6		; buffer := irq_mask (ACK cleared the IRQ's enable bit)
	dec	0
	ldi	0x13		; INTERRUPT_WRITE_ENABLED
	str	0
	out	7		; R0 -> counter
	lbr	isr_exit

	.data
	.global	irq_count
	.global	irq_mask
irq_mask:
	.byte	0x01		; mask      (isr_save_top-6)
	.byte	0		; scratch   (isr_save_top-5)
irq_count:
	.byte	0		; counter   (isr_save_top-4)
	.byte	0		; I/O buffer (isr_save_top-3)
	.byte	0, 0		; DF, D
isr_save_top:
	.byte	0		; T
