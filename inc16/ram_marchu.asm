; code: language=nasm tabSize=8

	; March RAM test algorithm:
	; step 0; up - w0 - write the test value
	; step 1; up - r0,w1,r1,w0
	; step 2; up - r0,w1
	; step 3; down - r1,w0,r0,w1
	; step 4; down - r1,w0
	;
	; XTRAMTEST-16 runs the march over 16-bit words (0000/FFFF), so every
	; access exercises both byte lanes, and errors are collected per data bit.


%include "defines.inc"

; ---------------------------------------------------------------------------
section_save ; MARK: __ save __





; ---------------------------------------------------------------------------
section .lib ; MARK: __ .lib __
; ---------------------------------------------------------------------------


; ---------------------------------------------------------------------------
; MARK: marchu
; perform march-U on 16K segments, a word at a time, using stack, with error reporting
; state registers:
;	ax = test value (0000 or FFFF)
;	bp = test step function
; output:
;	error bits are shown on the screen for each segment
marchu:
		mov	[ss:test_label], word scr_label_march
		mov	[ss:test_num], word 0
		mov	[ss:test_digits], byte 2

		xor	ax, ax			; test value for march is always 0

	.s0:	mov	bp, marchw_w0
		call	.test_up

	.s1:	mov	bp, marchw_r0w1r1w0
		call	.test_up

	.s2:	mov	bp, marchw_r0w1
		call	.test_up

		not	ax

	.s3:	mov	bp, marchw_r0w1r1w0
		call	.test_down

	.s4:	mov	bp, marchw_r0w1
		call	.test_down

		ret

.test_up:
		call	scr_test_announce
		call	ram_test_upwards
		jmp	.finish

.test_down:
		call	scr_test_announce
		call	ram_test_downwards
.finish:
		simulate_errors
		inc	word [ss:test_num]
		ret


; word-wide march test components
; inputs:
;	ax = test value (possibly inverted for second half of march test)
;	ds:di = es:di = start address (word aligned)
;	cx = number of words to test
;	dx = accumulated error bits
; preserves:
;	sp si dx bp
;	all segment registers
; state registers:
;	ax = test value (inverted at appropriate times)
;	bx = scratch: word read back, then its error bits
;	cx = word counter
;	es:di = current address under test
; output:
;	dx = accumulated error bits (dh = D8-D15, dl = D0-D7)

; ---------------------------------------------------------------------------
; MARK: marchw_w0
marchw_w0:	; w0
		rep 	stosw		; fill the range with the test value
		ret

; ---------------------------------------------------------------------------
; MARK: marchw_r0w1r1w0
marchw_r0w1r1w0:	; r0,w1,r1,w0
	.loop:	; r0
		mov	bx, [di]	; read the word [r0]
		xor	bx, ax		; compare the test value with the word
		or	dx, bx		; accumulate errors
		; w1
		not	ax		; now INVERTED
		mov	[di], ax	; write the inverted test value [w1]
		; r1
		mov	bx, [di]	; read the word [r1]
		xor	bx, ax		; compare the test value with the word
		or	dx, bx		; accumulate errors
		; w0
		not	ax		; now ORIGINAL
		stosw			; write the test value [w0], di += 2

		cmp	dx, 0xFFFF	; check for all bits in error to fail fast on empty banks
		je	.end		; if so, give up on this segment

		loop	.loop		; repeat for the next word

	.end:	ret			; segment done

; ---------------------------------------------------------------------------
; MARK: marchw_r0w1
marchw_r0w1:	; r0,w1
	.loop:	; r0
		mov	bx, [di]	; read the word [r0]
		xor	bx, ax		; compare the test value with the word
		or	dx, bx		; accumulate errors
		; w1
		not	ax		; now INVERTED
		stosw			; write the test value [w1], di += 2
		not	ax		; now ORIGINAL
		loop	.loop		; repeat for the next word

	.end:	ret			; segment done


; byte-wide march test components, used by marchu_nostack to find video RAM
; inputs:
;	al = test value (possibly inverted for second half of march test)
;	es:di = start address
;	cx = number of bytes to test
; preserves:
;	sp si bx dx
;	all segment registers
; state registers (saved between continuations):
;	al = test value (inverted at appropriate times)
;	cx = byte counter
;	es:di = current address under test
;	bp = return address
; output:
;	ah = error bits (0 = no error)
;	es:di = address of the error
;	bp = continuation address (for after errors)

; ---------------------------------------------------------------------------
; assumes DS=ES (stosb writes to ES:DI, [di] means [ds:di] by default
; MARK: marchu_r0w1r1w0
marchu_r0w1r1w0:	; r0,w1,r1,w0
	.loop:	; r0
		mov	ah, [di]	; read the byte [r0]
		xor	ah, al		; compare the test value with the byte
		or	dh, ah		; accumulate errors
		; w1
		not	al		; now INVERTED
		mov	[di], al	; write the inverted test value [w1]
		; r1
		mov	ah, [di]	; read the byte [r1]
		xor	ah, al		; compare the test value with the byte
		or	dh, ah		; accumulate errors
		; w0
		not	al		; now ORIGINAL
		stosb			; write the test value [w0], inc di

		cmp	dh, 0xFF	; check for all bits in error to fail fast on empty banks
		je	.end		; if so, give up on this segment

		loop	.loop		; repeat for the next byte

	.end:	ret			; segment done

; ---------------------------------------------------------------------------
; MARK: marchu_r0w1
marchu_r0w1:	; r0,w1
	.loop:	; r0
		mov	ah, [di]	; read the byte [r0]
		xor	ah, al		; compare the test value with the byte
		or	dh, ah		; accumulate errors
		; w1
		not	al		; now INVERTED
		stosb			; write the test value [w1], inc di
		not	al		; now ORIGINAL
		loop	.loop		; repeat for the next byte

	.end:	ret			; segment done


; ---------------------------------------------------------------------------
section_restore ; MARK: __ restore __
; ---------------------------------------------------------------------------





; ---------------------------------------------------------------------------
; MARK: test_dram
test_dram:
		mov	byte [ss:test_row], y_grid_march	; results go in the March-U grid
		call	marchu

