; code: language=nasm tabSize=8
%include "defines.inc"

; XTRAMTEST-16 screen layout (80x25):
;
;  row  0	title
;  row  1	byline
;  row  2	separator
;  row  3	status: SS, pass, current test, address range under test
;  rows 4-13	March-U results grid
;  rows 14-23	Bus Exercise results grid
;  row  24	legend
;
; Each grid has five columns of 128K, each with eight rows of 16K blocks.
; Every block shows the error bits found so far, split by byte lane:
;
;	March  Hi Lo
;	00-03  -- 04		(no errors in D8-D15, D2 bad)
;
; Hi is the high byte (odd addresses, D8-D15, bit 0 = D8), Lo is the low byte
; (even addresses, D0-D7).  The values are kept on the screen and read back
; at the start of each block, so errors accumulate across tests and passes.

%define xy(x,y) ((y<<8)|x)

y_title		equ	0
y_byline	equ	1
y_sep		equ	2
y_header	equ	3			; status line
y_grid_march	equ	4			; header row of the March-U grid
y_grid_bus	equ	14			; header row of the Bus Exercise grid
y_legend	equ	24

; ---------------------------------------------------------------------------
section_save
section .rwdata ; MARK: __ .rwdata __
; ---------------------------------------------------------------------------

	scrPos		dw	?	; pointer to current cursor position in screen memory
	scrAttr		db 	?	; current attribute for printing

	test_label	dw	?	; test label
	test_num	dw	?	; test number (March step) or pattern (Bus Exercise)
	test_digits	db	?	; number of hex digits of test_num to show (2 or 4)

	test_row	db	?	; header row of the grid for the current test

; ---------------------------------------------------------------------------
section .romdata ; MARK: __ .romdata __
; ---------------------------------------------------------------------------
x_grid_start	equ	7			; x of the left arrow in the first column
x_grid_loffs	equ	6			; the block label is this far left of the arrow
x_grid_width	equ	16			; width of each 128K column
grid_head_attr	equ	13h
grid_seg_attr	equ	13h
grid_k_attr	equ	07h

x_header_left	equ	1

x_ss		equ	x_header_left+4
y_ss		equ	y_header
x_pass		equ	x_ss+12
y_pass		equ	y_header
x_test		equ	x_pass+12
y_test		equ	y_header
x_range		equ	80-16-1
y_range		equ	y_header

; column headers: "Hi" and "Lo" sit over the two byte lanes of each block
scr_grid_march		asciiz	"March  Hi Lo"
scr_grid_bus		asciiz	"Bus    Hi Lo"

x_k_start		equ	x_grid_start-x_grid_loffs+1

%macro k_labels 1 ; y of the grid header
			db 	grid_k_attr, x_k_start,    %1+5, " 64K", 0
			db 	grid_k_attr, x_k_start+16, %1+5, "192K", 0
			db 	grid_k_attr, x_k_start+32, %1+5, "320K", 0
			db 	grid_k_attr, x_k_start+48, %1+5, "448K", 0
			db 	grid_k_attr, x_k_start+64, %1+5, "576K", 0
%endmacro

scr_k_labels:		k_labels y_grid_march
			k_labels y_grid_bus
			db	scr_test_label_attr,  x_ss-4,    y_ss,       "SS:", 0
			db	scr_test_label_attr,  x_pass-6,  y_pass,   "Pass:", 0
			db	scr_test_label_attr,  x_test-6,  y_test,   "Test:", 0
			db	scr_test_normal_attr, x_range+2, y_range, "00:0-  00:FFF", 0
%if SHOWSTACK == 0	; (the stack view uses the end of the last row)
			db	grid_head_attr, 1,  y_legend, "Hi", 0
			db	grid_k_attr,    3,  y_legend, " = high byte: odd addresses, D8-D15", 0
			db	grid_head_attr, 42, y_legend, "Lo", 0
			db	grid_k_attr,    44, y_legend, " = low byte: even addresses, D0-D7", 0
%endif
			db	0

scr_ss_xy		equ	xy( x_ss, y_ss )
scr_pass_xy		equ	xy( x_pass, y_pass )
scr_test_xy		equ	xy( x_test, y_test )
scr_addrs_xy		equ	xy( x_range, y_range )
scr_test_len		equ	(x_range-x_test)

scr_test_label_attr	equ	0x03
scr_test_normal_attr	equ	0x07
scr_test_header_attr	equ	0x0F

scr_label_march		asciiz	"March-U "
scr_label_bit		asciiz	"Bus Exercise "

scr_sep_char		equ	0xC4
scr_sep_attr		equ	0x02

scr_err_attr		equ	0x0C
scr_ok_attr		equ	0x07
scr_arrow_attr		equ	0x0A

; ---------------------------------------------------------------------------
section .lib ; MARK: __ .lib __
; ---------------------------------------------------------------------------

; get the byte value of two hex digits from the screen
; inputs:
;	[ss:scrPos] = address of the hex digits
; outputs:
;	ah = value of the hex digits
; destroys:
;	al
; MARK: scr_get_hex
scr_get_hex:
		push	di
		mov	di, [ss:scrPos]	; fetch the position
		mov	al, [ss:di]	; get the 4 MSB
		call	_h_to_u8	; convert to a number
		shl	al, 1		; put in the high nibble
		shl	al, 1
		shl	al, 1
		shl	al, 1
		mov	ah, al
		mov	al, [ss:di+2]	; get the 4 LSB
		call	_h_to_u8	; convert to a number
		or	ah, al
		pop	di
		ret


; convert an ascii hex digit in al to a number in al
; inputs:
;	al = ascii hex digit
; outputs:
;	al = value of the hex digit
; MARK: _h_to_u8
_h_to_u8:
		sub	al, '0'			;  > '0'?
		jb	.no			; no, return 0
		cmp	al, 9			; <= '9'?
		jbe	.done
		sub	al, 7			; look at A-F
		cmp	al, 0x0F		; <= 'F'?
		jbe	.done
		sub	al, 'a' - 'A'		; <= 'f'?
		cmp	al, 0x0F		; <= 'F'?
		jbe	.done
	.no	xor	al, al			; none of the above.  Return zero.
	.done	and	al, 0x0F		; strip any remaining high bits
		ret


; MARK: scr_clear
scr_clear:
		push	ax
		push	cx
		push	dx
		push	di
		push	es
		pushf
		cld

		mov	di, ss			; get the video memory segment from SS
		mov	es, di

		mov	ax,0700h+' '	; Attribute + space
		xor	di,di		; Start at first screen position.
		mov	cx,rwdata_base/2		; 2000 words.
		rep	stosw		; STOSW: AX-->[ES:DI], then DI=DI+2

		popf
		pop	es
		pop	di
		pop	dx
		pop	cx
		pop	ax
		ret


; MARK: scr_clear_line
scr_clear_line:
		push	ax
		mov	al, ' '
		call	scr_fill_line
		pop	ax
		ret


; MARK: scr_fill_line
scr_fill_line:
		push	cx
		push	dx

		call	scr_getxy
		xor	dl, dl
		call	scr_goto
		mov	cx, 80
		call	scr_fill

		pop	dx
		pop	cx
		ret


; input:
;	cx = number of characters to fill
;	al = character to fill with
; MARK: scr_fill
scr_fill:
		push	di
		push	es
		pushf

		mov	di, ss			; get the video memory segment from SS
		mov	es, di

		mov	ah, [ss:scrAttr]
		mov	di, [ss:scrPos]		; get current cursor position

		cld
		rep	stosw

		popf
		pop	es
		pop	di
		ret


; MARK: scr_test_announce
scr_test_announce:
		push	ax
		push	cx
		push	dx
		push	si
		push	ds

		mov	dx, cs				; we get strings from the ROM in CS
		mov	ds, dx

		mov	ah, scr_test_normal_attr
		call	scr_set_attr

		mov	dx, scr_ss_xy			; print the stack segment
		call	scr_goto
		mov	ax, ss
		call	scr_put_hex_ax

		mov	ah, scr_test_header_attr
		call	scr_set_attr

		mov	dx, scr_pass_xy			; print the pass count
		call	scr_goto
		mov	ax, [ss:pass_count]
		call	scr_put_hex_ax

		mov	dx, scr_test_xy			; print the test label
		call	scr_goto
		mov	cx, scr_test_len
		mov	al, ' '
		call	scr_fill
		mov	dx, scr_test_xy
		call	scr_goto
		mov	si, [ss:test_label]
		call	scr_puts

		; show the test's number (step for march, pattern for bus exercise)
		mov	ax, [ss:test_num]
		cmp	byte [ss:test_digits], 4
		je	.four
		mov	ah, al
		call	scr_put_hex_ah
		jmp	.done
	.four:	call	scr_put_hex_ax

	.done:	pop	ds
		pop	si
		pop 	dx
		pop	cx
		pop	ax
		ret


; input:
;	ds:si = struct: byte attr, byte x, byte y, string to print (null terminated), [then either more, or attr=0 to end]
; MARK: scr_puts_labels
scr_puts_labels:
		push	ax
		mov	al, [ss:scrAttr]
		push	ax
		push	di

		push	cs
		pop	ds


	.loop:	lodsb				; fetch the attribute
		cmp	al, 0			; check for last string
		je	.done			; if null, we're done
		mov	ah, al
		call	scr_set_attr
		lodsw				; fetch the x,y position
		mov	dx, ax			; ready the x,y pos for the goto call
		call	scr_goto
		call	scr_puts_nosave		; string will now be at [ds:si]
		jmp	.loop			; repeat

	.done:	pop	di
		pop	ax
		mov	[ss:scrAttr], al
		pop	ax
		ret


; input:
;	ds:si = string to print (null terminated)
; output:
;	ds:si = one byte past end of string
; MARK: scr_puts_nosave
scr_puts_nosave:
		push	ax
		push	cx
		push	es
		pushf
		cld

		mov	di, ss			; get the video memory segment from SS
		mov	es, di
		mov	di, [ss:scrPos]

		xor	cx, cx			; no count limit (well, 64KB)
		mov	ah, [ss:scrAttr]	; white on black

	.loop:	lodsb				; al := [ds:si], si += 1
		cmp	al, 0			; check for null terminator
		je	.done			; if null, we're done
		stosw				; [es:di] = ax, di += 2
		loop	.loop			; repeat

	.done:	mov	[ss:scrPos], di		; save new cursor position
		popf
		pop	es
		pop	cx
		pop	ax
		ret


; MARK: scr_puts
scr_puts:
		push 	si
		push	di
		call 	scr_puts_nosave
		pop	di
		pop	si
		ret


; input:
;	dh = y position
; 	dl = x position
; MARK: scr_goto
scr_goto:
		push	di
		call	calc_scr_pos
		mov	[ss:scrPos], di
		pop	di
		ret

; output:
;	dh = y position
; 	dl = x position
; MARK: scr_getxy
scr_getxy:
		push	ax

		mov	ax, [ss:scrPos]
		mov	dl, 160
		div	dl			; now al = y, ah = 2x
		shr	ah, 1			; now al = y, ah = x
		mov	dh, al
		mov	dl, ah

		pop	ax
		ret

; MARK: scr_newline
scr_newline:
		push	dx
		call	scr_getxy
		mov	dl, 0
		inc	dh
		; fall through to scr_vmove_epilog

; MARK: scr_vmove_epilog
scr_vmove_epilog:
		call	scr_goto
		pop	dx
		ret

; MARK: scr_rindex
scr_rindex:
		push	dx
		call	scr_getxy
		dec	dh
		jmp	scr_vmove_epilog


; input:
;	ah = attribute
; MARK: scr_set_attr
scr_set_attr:
		mov	[ss:scrAttr], ah
		ret

; input:
;	al = character
; MARK: scr_putc
scr_putc:
		push	ax
		push	di
		push	es
		pushf
		cld

		mov	di, ss			; get the video memory segment from SS
		mov	es, di

		mov	ah, [ss:scrAttr]	; get current attribute
		mov	di, [ss:scrPos]		; get current cursor position
		stosw				; [es:di] = ax, di += 2
		mov	[ss:scrPos], di		; save new cursor position

		popf
		pop	es
		pop	di
		pop 	ax
		ret


; input:
;	dh = y position
; 	dl = x position
; output:
;	di = screen position
;	(NO:) es = segment of screen memory
; MARK: calc_scr_pos
calc_scr_pos:
		push	ax
		push	dx

		mov	al, 160		; number of columns * 2 (for attribute)
		mul	dh		; ax := y * 160
		xor	dh, dh
		shl	dl, 1		; dx := x * 2 (for character and attribute)
		add	ax, dx		; add character offset
		mov	di, ax

		pop	dx
		pop	ax
		ret


; input:
;	ah = value to print
; MARK: scr_put_hex_ah_h
scr_put_hex_ah_h:	; print high nybble of ah as a hex digit
		push	cx
		mov	cx, 1
		jmp	__scr_put_hex


; input:
;	al = value to print
; MARK: scr_put_hex_ah_l
scr_put_hex_al_l:	; print the low nybble of bh as a hex digit
		push 	ax
		call 	__i2h_al
		call 	scr_putc
		pop	ax
		ret

; input:
;	ax = value to print
; MARK: scr_put_hex_ax
scr_put_hex_ax:
		push	cx
		mov	cx, 4		; 4 nybbles in ax
		jmp	__scr_put_hex

; input:
;	ah = value to print
; MARK: scr_put_hex_ah
scr_put_hex_ah:
		push 	cx
		mov	cx, 2		; 2 nybbles in ah
		; fall through to __scr_put_hex

; input:
;	ax = value to print (upper nybble first)
;       cx = number of nybbles to print
; MARK: __scr_put_hex
__scr_put_hex:
		push 	ax
		push	bx

	.loop:	rol	ax, 1		; rol	bx, 4
		rol	ax, 1
		rol	ax, 1
		rol	ax, 1

	.put:
		mov	bx, ax		; save the value
		call	__i2h_al	; convert to ASCII
		call	scr_putc
		mov	ax, bx
		loop	.loop

		pop	bx
		pop	ax
		pop	cx
		ret

; input:
;	al = value to convert
; MARK: __i2h_al
__i2h_al:	; convert low nybble of al to ASCII
		and	al,0fh
		add	al,90h
		daa
		adc	al,40h
		daa
		ret


; print the error bits of one byte lane: "--" if none, otherwise hex
; input:
;	ah = error bits
; MARK: scr_put_errs
scr_put_errs:
		or	ah, ah
		jz	.ok
		mov	byte [ss:scrAttr], scr_err_attr
		jmp	scr_put_hex_ah

	.ok:	mov	byte [ss:scrAttr], scr_ok_attr
		push	ax
		mov	al, '-'
		call	scr_putc
		call	scr_putc
		pop	ax
		ret


; move to the left arrow of a block's results in the current test's grid
; input:
;	al = segment (high byte)
;	[ss:test_row] = header row of the grid
; MARK: scr_goto_seg
scr_goto_seg:
		push	ax
		push	dx

		; calculate y
		mov	ah, al
		and	ah, 1Fh			; mask out the upper bits
		shr	ah, 1
		shr	ah, 1			; ah = row within the column (0-7)

		mov	dh, [ss:test_row]	; header row of the grid
		inc	dh			; first row of blocks
		add	dh, ah
		test	al, 10h
		jz	.not_upper
		inc	dh			; skip the 64K label row
	.not_upper:
		; calculate x
		mov 	dl, al
		and	dl, 0xE0		; mask out the lower bits
		shr	dl, 1			; column * 16
		add	dl, x_grid_start	; add the base x position

		call	scr_goto
		pop	dx
		pop	ax
		ret


; draw one results grid: column headers and block labels
; input:
;	si = column header text
;	[ss:test_row] = header row of the grid
; MARK: draw_ram_grid
draw_ram_grid:
		push	ds
		push	cs			; set up to copy from ROM to VRAM
		pop	ds

		mov	ah, grid_head_attr
		call	scr_set_attr
		mov	dh, [ss:test_row]	; go to the start of the grid
		mov	dl, x_grid_start-x_grid_loffs
		mov	cx, 5
	.hloop:	call	scr_goto
		call	scr_puts		; print the header for this column
		add	dl, x_grid_width
		loop	.hloop

		mov	ah, grid_seg_attr
		call	scr_set_attr

		; now print the block labels
		mov	cx, num_segments
		mov	al, 0			; segment counter
	.lloop:
		call	scr_goto_seg
		sub	word [ss:scrPos], x_grid_loffs*2	; go back for label
		mov	ah, al
		call	scr_put_hex_ah
		mov	al, '-'		; print the dash
		call	scr_putc
		add	ah, 3
		call	scr_put_hex_ah
		mov	al, ah
		inc	al
		loop	.lloop

		pop	ds
		ret


; MARK: draw_screen
draw_screen:
		xor	dx, dx
		call	scr_goto
		mov	ah, title_attr
		call	scr_set_attr
		call	scr_clear_line

		mov	si, title_text
		call	scr_puts_labels

		mov	ah, scr_sep_attr
		call	scr_set_attr

		mov	dx, xy(0, y_sep)
		call	scr_goto
		mov	al, scr_sep_char
		call	scr_fill_line

		mov	byte [ss:test_row], y_grid_march
		mov	si, scr_grid_march
		call	draw_ram_grid

		mov	byte [ss:test_row], y_grid_bus
		mov	si, scr_grid_bus
		call	draw_ram_grid

		mov	si, scr_k_labels
		call	scr_puts_labels
		ret


; ---------------------------------------------------------------------------
section_restore ; MARK: __ restore __
; ---------------------------------------------------------------------------
