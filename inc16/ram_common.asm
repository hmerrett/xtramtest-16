; code: language=nasm tabSize=8
%include "defines.inc"

; Common code for the 16-bit RAM tests.
;
; Memory is tested a word at a time, so every access uses the full 16-bit
; data bus.  Errors are accumulated as a word of bits in DX: DH holds the
; high byte (odd addresses, D8-D15) and DL the low byte (even addresses,
; D0-D7), and the two halves are reported separately on the screen.

seg_start	equ	0

; ---------------------------------------------------------------------------
section_save
; ---------------------------------------------------------------------------
section .lib ; MARK: __ .lib __
; ---------------------------------------------------------------------------

; %define SIMULATE_ERRORS

%ifdef SIMULATE_ERRORS
	%define simulate_errors call _do_sim_errors

	%macro _sim_error 1-3 0,1	; segment, offset, bits to flip
		mov	ax, %1
		mov	es, ax
		xor	[es:%2], byte %3
	%endmacro

_do_sim_errors:
		push	ax
		push	es

		_sim_error 0x0000, 1, 0x80	; odd byte: high byte, D15
		_sim_error 0x1000, 0, 0x02	; even byte: low byte, D1

		pop	es
		pop	ax
		ret
%else
	%define simulate_errors
%endif


; MARK: ram_test_upwards
ram_test_upwards:
; run the test step in bp over all of the segments, from the bottom up
; inputs:
;	ax = test value
;	bp = test step function
; state variables:
;	bx = segment under test
;	dx = error bits for the segment under test (0 = no error)

		cld			; clear the direction flag (go up)
		mov	bx, first_segment

	.segment_loop:
		xor	di, di		; start at the beginning of the segment

		call	ram_test_segment

		add	bx, bytes_per_segment/16		; next segment
		cmp	bx, first_segment + num_segments*(bytes_per_segment/16)
		jne	.segment_loop	; if not past the end, continue
		ret


; MARK: ram_test_downwards
ram_test_downwards:
; run the test step in bp over all of the segments, from the top down

		std			; set the direction flag (go down)
		mov	bx, first_segment + (num_segments-1)*(bytes_per_segment/16)	; start at last segment

	.segment_loop:
		mov	di, bytes_per_segment-2		; start at the last word of the segment

		call	ram_test_segment

		sub	bx, bytes_per_segment/16		; next segment down
		cmp	bx, first_segment - bytes_per_segment/16
		jne	.segment_loop	; if not past the beginning, continue

		cld
		ret


; MARK: ram_test_segment
; inputs:
;	ax = test value
;	bx = segment to test
;	di = first word to test
;	bp = test step function
ram_test_segment:
		mov	es, bx		; set the segment to test
		mov	ds, bx

		call	startseg	; dx := errors already found in this segment

		cmp	dx, 0xFFFF	; check if this segment is all errors (probably missing)
		je	.nextseg	; if so, don't bother testing it again

		push	ax
		push	bx
		mov	cx, bytes_per_segment/2		; number of words to test
		call	bp		; run the specified step
		pop	bx
		pop	ax

	.nextseg:
		call	endseg
		ret



; MARK: startseg
; Show on the screen that we are starting this segment, and fetch the
; errors already shown for it.
; inputs:
;	es = segment under test
; outputs:
;	dh = high byte (D8-D15) error bits so far
;	dl = low byte (D0-D7) error bits so far
startseg:
		push	ax

		mov	dx, scr_addrs_xy		; print the test addresses
		call	scr_goto

		mov	[ss:scrAttr], byte scr_test_header_attr
		mov	ax, es
		call	scr_put_hex_ah

		add	word [ss:scrPos], 5*2		; skip over "00:0-"

		add	ax, bytes_per_segment/16 - 0x100
		call	scr_put_hex_ah

		mov	al, ah
		call	scr_goto_seg

		mov	[ss:scrAttr], byte scr_arrow_attr
		mov	al, 10h
		call	scr_putc

		call	scr_get_hex	; get the high byte errors shown at this location
		mov	dh, ah

		add	word [ss:scrPos], 3*2		; skip "HH " to the low byte
		call	scr_get_hex	; get the low byte errors
		mov	dl, ah

		add	word [ss:scrPos], 2*2
		mov	al, 11h
		call	scr_putc

		pop	ax
		ret

; MARK: endseg
endseg:
		; show on the screen that we have finished this segment
		push	ax

		mov	ax, es
		mov	al, ah
		call	scr_goto_seg	; position the cursor for the report for this segment

		mov	[ss:scrAttr], byte scr_arrow_attr
		mov	al, " "
		call	scr_putc

		mov	ah, dh
		call	scr_put_errs	; print the high byte error bits

		mov	al, " "
		call	scr_putc

		mov	ah, dl
		call	scr_put_errs	; print the low byte error bits

		mov	[ss:scrAttr], byte scr_arrow_attr
		mov	al, " "
		call	scr_putc

		pop	ax
		ret

; ---------------------------------------------------------------------------
section_restore ; MARK: __ restore __
; ---------------------------------------------------------------------------
