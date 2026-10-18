; code: language=nasm tabSize=8
%include "defines.inc"

; ---------------------------------------------------------------------------
section_save
; ---------------------------------------------------------------------------
section .lib ; MARK: __ .lib __
; ---------------------------------------------------------------------------





; MARK: ram_test_ganssle
ram_test_ganssle: ; perform bus tests, using stack, with error reporting
		mov	[ss:test_label], word scr_label_bit
		mov	[ss:test_digits], byte 4

		mov	ax, 0xFFFF
		call	ganssle_one_test
		mov 	ax, 0x0000
		call	ganssle_one_test
		mov	ax, 0x5555
		call	ganssle_one_test
		mov	ax, 0xAAAA
		call	ganssle_one_test
		mov	ax, 0xFF00		; opposite values in the two byte lanes
		call	ganssle_one_test
		mov	ax, 0x00FF
		call	ganssle_one_test

		ret

ganssle_one_test:
		mov	[ss:test_num], ax
		call	scr_test_announce
		mov	bp, ganssle_segment
		call	ram_test_upwards
		ret


; One step of the bus exercise: write the pattern high in the segment, read
; it back, write its inverse low in the segment one byte lane at a time,
; copy that back up as a word, and check it.  %1 = L or H selects which byte
; lane is written first: a byte write that also hits the other lane (a BHE#
; or A0 fault) is only visible if that lane was already written.
%macro ganssle_step 1
		dec	di		; decrement DI to next lower word
		dec	di
		mov	[di], ax	; write [es:di] with original test value
		mov	bx, [di]	; read back [es:di]
		not	bx		; invert the value
	%ifidn %1, L
		mov	[si], bl	; write inverted to [es:si], low byte lane first
		mov	[si+1], bh
	%else
		mov	[si+1], bh	; write inverted to [es:si], high byte lane first
		mov	[si], bl
	%endif
		movsw			; copy [es:di] := [ds:si], si+=2, di+=2 (read, write)
		dec	di		; rewind to just-written value
		dec	di
		mov	bx, [di]	; read the final inverted value back
		not	bx		; invert the value (back to original)
		xor	bx, ax		; compare the final value to the test value
		or	dx, bx		; accumulate errors
%endmacro


; inputs:
;	ax = test value
;	ds,es = segment to test
;	cx = number of words to test (even)
; 	dx = accumulated error bits
; preserves:
;	ax sp bp
;	all segment registers
; state registers:
;	ax = test value
;	bx = scratch
;	cx = word pair counter
;	ds:si = low address under test (going up)
;	es:di = high address under test (going down)
; output:
;	dx = accumulated error bits (dh = D8-D15, dl = D0-D7)
;
; this test attempts to use some of the concepts introduced by this article:
; https://www.ganssle.com/testingram.htm
;
; MARK: ganssle_segment
ganssle_segment:
		; data bus test: walk a one, then a zero, through all 16 data
		; lines using the first word of the segment
		push	ax
		mov	ax, 1
	.walk:	mov	[0], ax		; walking one
		mov	bx, [0]
		xor	bx, ax
		or	dx, bx		; accumulate errors
		not	ax		; walking zero
		mov	[0], ax
		mov	bx, [0]
		xor	bx, ax
		or	dx, bx		; accumulate errors
		not	ax
		shl	ax, 1		; next data line
		jnz	.walk		; until the one falls off the top
		pop	ax

		xor	si, si		; start SI at the beginning of the segment
		mov	di, cx		; start DI at (just past) the end of the segment
		shl	di, 1
		shr	cx, 1		; two words per loop

	.loop:	cmp	dx, 0xFFFF	; check for all bits in error
		je	.end		; if so, give up on this segment
		ganssle_step L
		ganssle_step H
		loop	.loop		; continue until the segment is done

	.end:	ret			; done

; ---------------------------------------------------------------------------
section_restore ; MARK: __ restore __
; ---------------------------------------------------------------------------





; MARK: test_ganssle
test_ganssle:
		mov	byte [ss:test_row], y_grid_bus	; results go in the Bus Exercise grid
		call	ram_test_ganssle
