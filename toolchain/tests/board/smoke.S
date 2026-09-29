; smoke.S — sim1802 board smoke test (Step 03).  Freestanding: no libc, no
; NCRT; exercises exactly what the board definition promises:
;   reset at 0x0000 with X=P=0, R0=0, IE=1   [MPM-201A p. 72, Fig. 86]
;   ROM 0x0000-0x7FFF write-protected, RAM 0x8000-0xFFFF
;   .data copied from ROM to RAM, .bss cleared
;   console output (OUT 6 byte, OUT 7 0xE0)
;   cycle timer (mode 4) on IRQ 0, standard R2-stack ISR, IDL
; Register convention (ADR 0006): R1 = interrupt PC (hardware), R2 = stack
; pointer, always valid for the ISR (X=2 on interrupt), R3 = program counter
; after reset, R0 never used after reset (free for DMA).
;   halt with status (OUT 6 status, OUT 7 0x00)
; Prints "sim1802 board ok, ticks=5" and exits with status 0.

#define PERIOD	5000		/* machine cycles = 10 ms at 4 MHz */
#define TICKS	5

	.section .reset,"ax"
	.global	__start
__start:			; reset: P=0, X=0, R0=0x0000, IE=1
	dis			; M(R(X)) -> X,P: the next byte, 0x00 -> X=0,P=0; IE=0
	.byte	0x00
	ldi	%hi(main)
	phi	3
	ldi	%lo(main)
	plo	3
	sep	3		; PC := R3 (convention); R0 is left free for DMA

	.text
main:
	ldi	0xff		; SP := 0xFFFF, top of RAM
	phi	2
	plo	2
	sex	2

#ifndef SMOKE_NO_DATA_COPY	/* negative test: RAM is not zero at power-on */
	; copy .data: R8 = _eronly (ROM), R9 = _sdata, R10 = _edata
	ldi	%hi(_eronly)
	phi	8
	ldi	%lo(_eronly)
	plo	8
	ldi	%hi(_sdata)
	phi	9
	ldi	%lo(_sdata)
	plo	9
	ldi	%hi(_edata)
	phi	10
	ldi	%lo(_edata)
	plo	10
1:	glo	9		; while (R9 != R10)
	str	2
	glo	10
	xor
	lbnz	2f
	ghi	9
	str	2
	ghi	10
	xor
	lbz	3f
2:	lda	8
	str	9
	inc	9
	lbr	1b

#endif
	; clear .bss: R9 = _sbss, R10 = _ebss
3:	ldi	%hi(_sbss)
	phi	9
	ldi	%lo(_sbss)
	plo	9
	ldi	%hi(_ebss)
	phi	10
	ldi	%lo(_ebss)
	plo	10
4:	glo	9
	str	2
	glo	10
	xor
	lbnz	5f
	ghi	9
	str	2
	ghi	10
	xor
	lbz	6f
5:	ldi	0
	str	9
	inc	9
	lbr	4b

6:	; interrupts: R1 = ISR entry; the ISR saves context on R2
	ldi	%hi(isr_entry)
	phi	1
	ldi	%lo(isr_entry)
	plo	1

	; timer: period, enable IRQ 0, mode 4
	ldi	(PERIOD & 0xff)
	plo	7
	ldi	0x81
	plo	8
	lbr	cmd_then_7
7:	ldi	((PERIOD >> 8) & 0xff)
	plo	7
	ldi	0x82
	plo	8
	lbr	cmd_then_8
8:	ldi	((PERIOD >> 16) & 0xff)
	plo	7
	ldi	0x83
	plo	8
	lbr	cmd_then_9
9:	ldi	0x01		; IRQ 0 enabled
	plo	7
	ldi	0x13
	plo	8
	lbr	cmd_then_10
10:	ldi	4		; timer mode 4 (cycles)
	plo	7
	ldi	0x80
	plo	8
	lbr	cmd_then_11
11:	sex	3		; IE := 1, X=2, P=3
	ret
	.byte	0x23

	ldi	TICKS		; R11.0 = number of IDLs
	plo	11
12:	idl			; wakes on IRQ 0, ISR runs, returns here
	dec	11
	glo	11
	lbnz	12b

	sex	3		; IE := 0
	dis
	.byte	0x23

	ldi	%hi(msg)	; print "sim1802 board ok, ticks="
	phi	8
	ldi	%lo(msg)
	plo	8
13:	lda	8
	lbz	14f
	str	2
	out	6
	dec	2
	ldi	0xe0
	str	2
	out	7
	dec	2
	lbr	13b

14:	ldi	%hi(ticks)	; print the tick counter, then newline
	phi	8
	ldi	%lo(ticks)
	plo	8
	ldn	8
	str	2
	out	6
	dec	2
	ldi	0xe0
	str	2
	out	7
	dec	2
	ldi	0x0a
	str	2
	out	6
	dec	2
	ldi	0xe0
	str	2
	out	7
	dec	2

#ifdef SMOKE_WRITE_ROM
	ldi	0		; negative test: store into ROM must trap (97)
	phi	8
	plo	8
	str	8
#endif

	ldi	0		; halt, status 0
	str	2
	out	6
	dec	2
	ldi	0x00
	str	2
	out	7
	idl			; not reached

; "Subroutines" without NCRT: send command R8.0 with argument R7.0, then
; jump back to the given label (one entry per return point keeps it simple).
cmd:	glo	7
	str	2
	out	6
	dec	2
	glo	8
	str	2
	out	7
	dec	2
	sep	5		; unused
cmd_then_7:
	glo	7
	str	2
	out	6
	dec	2
	glo	8
	str	2
	out	7
	dec	2
	lbr	7b
cmd_then_8:
	glo	7
	str	2
	out	6
	dec	2
	glo	8
	str	2
	out	7
	dec	2
	lbr	8b
cmd_then_9:
	glo	7
	str	2
	out	6
	dec	2
	glo	8
	str	2
	out	7
	dec	2
	lbr	9b
cmd_then_10:
	glo	7
	str	2
	out	6
	dec	2
	glo	8
	str	2
	out	7
	dec	2
	lbr	10b
cmd_then_11:
	glo	7
	str	2
	out	6
	dec	2
	glo	8
	str	2
	out	7
	dec	2
	lbr	11b

; ISR, the standard R2-stack form [MPM-201A p. 65, Fig. 76]: entry with
; P=1, X=2, IE=0.  DEC 2 first, because the interrupted code may be using
; M(R2) (compiled code keeps a scratch byte there).  Frame, from the top:
;   T (X,P of the interrupted code), D, DF, R15.0, R15.1
; RET at the end restores X,P from T and sets IE=1; because the exit code
; sits right before the entry, R1 is left pointing at isr_entry again.
isr_exit:
	lda	2		; R15.1
	phi	15
	lda	2		; R15.0
	plo	15
	lda	2		; DF byte
	shr			; DF := bit 0
	lda	2		; D
	ret			; X,P := T, R2++, IE := 1
isr_entry:
	dec	2
	sav			; push T
	dec	2
	str	2		; push D
	shlc			; D.0 := DF
	dec	2
	str	2		; push DF
	glo	15
	dec	2
	str	2		; push R15.0
	ghi	15
	dec	2
	str	2		; push R15.1

	ldi	%hi(ticks)	; ticks++
	phi	15
	ldi	%lo(ticks)
	plo	15
	ldn	15
	adi	1
	str	15

	dec	2		; OUT reads M(R2) and increments R2: net 0
	ldi	0x10		; acknowledge
	str	2
	out	7
	dec	2
	inp	6		; D := IRQ number (ignored: only IRQ 0 is enabled)
	ldi	0x01		; re-enable IRQ 0 (ACK cleared its enable bit)
	str	2
	out	6
	dec	2
	ldi	0x13
	str	2
	out	7
	lbr	isr_exit

	.section .rodata
msg:	.asciz	"sim1802 board ok, ticks="

	.data			; copied from ROM at start-up
ticks:	.byte	'0'		; initialised data: proves the .data copy

	.bss
	.global	bss_probe
bss_probe:
	.space	4
