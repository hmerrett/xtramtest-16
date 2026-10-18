; XTRAMTEST-16: the XTRAMTEST RAM test ROM for 16-bit (8086 and 80286) machines.
;
; Memory is tested a word at a time over the full 16-bit data bus, and the
; errors for each 16K block are shown separately for the high byte (odd
; addresses, D8-D15) and the low byte (even addresses, D0-D7), so a fault can
; be traced to the chips of the right byte lane.  Build with -iinc16.

; --- refresh time delay ---
%define REFRESH_DELAY 5

; ************************************************************************************************
%include "defines.inc"

[map all xtramtest16.map]

START		equ	00000h
RESET		equ	01FF0h
BASESEG		equ	0FE00h

section .text		start=START align=1
section .lib		follows=.text align=1
section .romdata	follows=.lib align=1
section .resetvec 	start=RESET align=1


; .rwdata section in the unused portion of MDA/CGA video RAM, starting at 4000 DECIMAL - 96 bytes.
; variables at the bottom, stack at the top.
section .rwdata		start=rwdata_base align=1 nobits
rwdata_start:

%define first_segment 0
%define num_segments 40
%define bytes_per_segment 0x4000

; ---------------------------------------------------------------------------
section .rwdata ; MARK: __ .rwdata __
; ---------------------------------------------------------------------------
;Variables stored in unused MDA/CGA video RAM, or 4 KB at A0000.
; ---------------------------------------------------------------------------
	pass_count	dw	?			; The number of passes completed. Incremented by 1 each time a pass is completed.

	do_not_use	equ	rwdata_base+38		; Do not use this location. It caused a problem if a Mini G7 video card was used.

; ---------------------------------------------------------------------------
section .romdata ; MARK: __ .romdata __

title_attr	equ	0Fh
subtitle_attr	equ	07h
byline_attr	equ	02h

%defstr VERSION_STRING VERSION

title_text: ; attr, x, y, text, 0 (terminate with 0 for attr)
			db 	title_attr,   1, y_title
	title_only:	db	"XTRAMTEST-16 ", 0
			db	subtitle_attr, 14, y_title
			db	VERSION_STRING, " (", __DATE__, ")", 0
			db	title_attr,  48, y_title, "github.com/hmerrett/xtramtest-16", 0
			db	byline_attr,  0, y_byline, "by Dave Giller - with Adrian Black - https://youtube.com/@AdriansDigitalBasement", 0
			db	0

; ---------------------------------------------------------------------------
section .lib ; MARK: __ .lib __
; ---------------------------------------------------------------------------

; procedures to include in the ROM
%include "screen.asm"
%include "ram_common.asm"
%include "ram_marchu_nostack.asm"

; ---------------------------------------------------------------------------
section .text ; MARK: __ .text __
; ---------------------------------------------------------------------------

%include "option_rom.asm"

; ************************************************************************************************
; Initialization modules
%include "010_cold_boot.inc"
%include "030_video.inc"

xtramtest_start:
		%include "050_beep.inc"
		%include "060_vram.inc"

		call	scr_clear
		call 	draw_screen

		; Disable maskable interrupts, and set the direction flag to increment.
		cli
		cld

xtramtest_loop:
		add	word [ss:pass_count], 1		; Increment the pass count.

		%include "ram_marchu.asm"
		%include "ram_ganssle.asm"

		jmp	xtramtest_loop


;------------------------------------------------------------------------------
; Power-On Entry Point
;------------------------------------------------------------------------------
section .resetvec ; MARK: __ .resetvec __
; ---------------------------------------------------------------------------
PowerOn:	jmp	BASESEG:cold_boot	; CS will be 0F000h

S_FFF5:		db __DATE__		; Assembled date (YYYY-MM-DD)
		db 0			; space for checksum byte


section .rwdata
rwdata_end:
