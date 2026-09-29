; isr_r2.S — the standard COSMAC interrupt routine (RCA MPM-201A Fig. 76,
; ADR 0006): R1 = interrupt PC, context saved on the R2 stack, R0 unused.
; Counts interrupts, acknowledges the sim1802 interrupt controller and
; re-enables IRQ 0.  Validation code for toolchain issue 0001 / ADR 0007.

	.text

; void isr_r2_install(void): R1 := isr_r2_entry
	.global	isr_r2_install
	.type	isr_r2_install, @function
isr_r2_install:
	ldi	%hi(isr_r2_entry)
	phi	1
	ldi	%lo(isr_r2_entry)
	plo	1
	sep	5
	.size	isr_r2_install, .-isr_r2_install

; Frame (from the top): T, D, DF, R15.0, R15.1, BUF.  BUF is the I/O
; controller's argument buffer: interrupted code may be between its OUT 6
; (argument) and OUT 7 (command), so the handler must give it back unchanged.
; The exit code precedes the entry, so RET leaves R1 pointing at
; isr_r2_entry again.
	.type	isr_r2, @function
isr_r2:
isr_r2_exit:
	out	6		; restore the I/O buffer (pops BUF)
	lda	2		; R15.1
	phi	15
	lda	2		; R15.0
	plo	15
	lda	2		; DF
	shr
	lda	2		; D
	ret			; X,P := T; R2++; IE := 1
isr_r2_entry:
	dec	2		; protect M(R2), the interrupted code's scratch byte
	sav
	dec	2
	str	2
	shlc
	dec	2
	str	2
	glo	15
	dec	2
	str	2
	ghi	15
	dec	2
	str	2
	dec	2
	inp	6		; push the I/O buffer (INP stores to M(R2))

	ldi	%hi(isr_r2_count+3)	; isr_r2_count++ (32-bit, big-endian)
	phi	15
	ldi	%lo(isr_r2_count+3)
	plo	15
	ldn	15
	adi	1
	str	15
	dec	15
	ldn	15
	adci	0
	str	15
	dec	15
	ldn	15
	adci	0
	str	15
	dec	15
	ldn	15
	adci	0
	str	15

	dec	2		; acknowledge: OUT reads M(R2), R2++ (net 0)
	ldi	0x10
	str	2
	out	7
	dec	2
	inp	6		; IRQ number (only IRQ 0 is enabled)
	ldi	0x01		; re-enable IRQ 0
	str	2
	out	6
	dec	2
	ldi	0x13
	str	2
	out	7
	lbr	isr_r2_exit
	.size	isr_r2, .-isr_r2

	.data
	.global	isr_r2_count
isr_r2_count:
	.word	0		; 32-bit: long runs exceed 65535 interrupts
