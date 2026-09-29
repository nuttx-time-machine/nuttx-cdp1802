; head.S -- reset code and I/O helpers for the code-banking test (Step 06b).
; Same start-up as arch/cosmac/src/cdp1802/cdp1802_head.S, freestanding:
; reset, SP, PC := R3, .data copy, .bss clear, NCRT (R4/R5), bank state,
; main(), then exit with main's return value as the simulator status.

	.section .reset, "ax"
	.global	__start
__start:
	dis			; IE := 0 (IE = 1 after reset, MPM p. 72)
	.byte	0x00
	ldi	0xff		; SP := 0xFFFF (top of RAM)
	phi	2
	plo	2
	ldi	%hi(start_c)
	phi	3
	ldi	%lo(start_c)
	plo	3
	sep	3

	.text
start_c:
	sex	2
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
1:	glo	9
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
6:	ldi	%hi(cosmac_ncrt_call)
	phi	4
	ldi	%lo(cosmac_ncrt_call)
	plo	4
	ldi	%hi(cosmac_ncrt_ret)
	phi	5
	ldi	%lo(cosmac_ncrt_ret)
	plo	5
	sep	4
	.hword	cosmac_bank_initialize
	sep	4
	.hword	main
	; fall through: exit(R7.0)

; void sim_exit(int status)
	.global	sim_exit
sim_exit:
	sex	2
	glo	7
	str	2
	out	6
	dec	2
	ldi	0x00		; halt command
	str	2
	out	7
7:	br	7b

; void putch(char c)
	.global	putch
putch:
	glo	7
	str	2
	out	6
	dec	2
	ldi	0xe0		; console output command
	str	2
	out	7
	dec	2
	sep	5
