; isr_bank.S -- interrupt routine for the code-banking test (Step 06b).
; A standard R1/R2 interrupt routine (ADR 0006) that saves everything a C
; call may change (D, DF, R3..R10 and the I/O buffer) and calls the
; C function isr_hook(), which lives in a bank: interrupt handlers reach
; banked code through the stubs, whatever bank the interrupted code had
; selected.
; R4 and R5 are saved and reloaded too: the interrupt may arrive while the
; NCRT call or return routine runs (P=4 or P=5), and then R4 or R5 points
; into the middle of it.

	.text
	.global	isr_bank_install
isr_bank_install:
	ldi	%hi(isr_entry)
	phi	1
	ldi	%lo(isr_entry)
	plo	1
	sep	5

isr_exit:
	inc	2		; back to the I/O buffer byte
	out	6		; restore the I/O buffer (pops it)
	lda	2
	phi	10
	lda	2
	plo	10
	lda	2
	phi	9
	lda	2
	plo	9
	lda	2
	phi	8
	lda	2
	plo	8
	lda	2
	phi	7
	lda	2
	plo	7
	lda	2
	phi	6
	lda	2
	plo	6
	lda	2
	phi	5
	lda	2
	plo	5
	lda	2
	phi	4
	lda	2
	plo	4
	lda	2
	phi	3
	lda	2
	plo	3
	lda	2		; DF
	shr
	lda	2		; D
	ret			; X,P := T; IE := 1
isr_entry:
	dec	2		; keep the interrupted code's free byte
	sav
	dec	2
	str	2		; D
	shlc
	dec	2
	str	2		; DF
	glo	3
	dec	2
	str	2
	ghi	3
	dec	2
	str	2
	glo	4
	dec	2
	str	2
	ghi	4
	dec	2
	str	2
	glo	5
	dec	2
	str	2
	ghi	5
	dec	2
	str	2
	glo	6
	dec	2
	str	2
	ghi	6
	dec	2
	str	2
	glo	7
	dec	2
	str	2
	ghi	7
	dec	2
	str	2
	glo	8
	dec	2
	str	2
	ghi	8
	dec	2
	str	2
	glo	9
	dec	2
	str	2
	ghi	9
	dec	2
	str	2
	glo	10
	dec	2
	str	2
	ghi	10
	dec	2
	str	2
	dec	2
	inp	6		; push the I/O buffer
	dec	2		; C convention: M(SP) is free

	ldi	0x10		; acknowledge (only IRQ 0 is enabled)
	str	2
	out	7
	dec	2
	inp	6
	ldi	0x01		; re-enable IRQ 0
	str	2
	out	6
	dec	2
	ldi	0x13
	str	2
	out	7
	dec	2

	ldi	%hi(cosmac_ncrt_call)
	phi	4
	ldi	%lo(cosmac_ncrt_call)
	plo	4
	ldi	%hi(cosmac_ncrt_ret)
	phi	5
	ldi	%lo(cosmac_ncrt_ret)
	plo	5
	ldi	%hi(1f)		; call isr_hook() with R3 as the PC
	phi	3
	ldi	%lo(1f)
	plo	3
	sep	3
	lbr	isr_exit
1:	sep	4
	.hword	isr_hook
	sep	1
