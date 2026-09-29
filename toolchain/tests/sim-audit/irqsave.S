; irqsave.S — LSIE-based up_irq_save()/up_irq_restore() sketch from
; docs/journal/step-02.md (Q4), exercised by irqsave.c.  Validation only.

	.text
	.global	sketch_irq_save
sketch_irq_save:
	ldi	0
	phi	7
	ldi	1		; assume IE=1
	lsie			; IE=1: skip the LDI 0
	ldi	0		; IE was 0
	plo	7
	sex	3
	dis			; IE := 0
	.byte	0x23		; X=2, P=3
	sep	5

	.global	sketch_irq_restore
sketch_irq_restore:
	glo	7
	lbz	1f		; long branch: BZ only reaches its own 256-byte page
	sex	3
	ret			; IE := 1
	.byte	0x23
	sep	5
1:	sex	3
	dis			; IE := 0
	.byte	0x23
	sep	5
