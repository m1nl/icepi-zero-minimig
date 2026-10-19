; Minimig.card - P96 RTG driver for the Minimig Amiga core

; Adapted by Alastair M. Robinson from a similar project
; for the Replay board - WWW.FPGAArcade.COM

; Replay.card - P96 RTG driver for the REPLAY Amiga core
; Copyright (C) FPGAArcade community
;
; Contributors : Jakub Bednarski, Mike Johnson, Jim Drew, Erik Hemming, Nicolas Hamel
;
; This software is licensed under LPGLv2.1 ; see LICENSE file


; 0.1 - Cut down to the bare bones...

	machine 68020

	include lvo/exec_lib.i
	include lvo/intuition_lib.i
	include lvo/expansion_lib.i
	include lvo/graphics_lib.i
	include exec/exec.i
	include intuition/intuitionbase.i
	include libraries/expansionbase.i
	include hardware/intbits.i
	include exec/interrupts.i


	include libraries/Picasso96.i
	include boardinfo.i
	include settings.i

; CardData is a region of 16 longwords, so 64 bytes we can use as we please
CardData_IntEnabled = gbi_CardData+24
CardData_ModeValid = gbi_CardData+26
CardData_VRepeat = gbi_CardData+28
CardData_VOrigin = gbi_CardData+30
CardData_VStop = gbi_CardData+32
CardData_SourceWidth = gbi_CardData+34

; HDMI-timed RTG registers, relative to $B80100.
RTG_STATUS = $0c       ; read: blank, pending, enabled, active (bits 0..3)
RTG_IRQ_CONTROL = $0c  ; write: enable bit0, acknowledge bit1 (W1C)
RTG_DISPLAY_SWITCH = $10 ; read/write bit0: 0 native, 1 RTG
RTG_SPLIT_ROW = $12    ; first secondary-framebuffer row, $7ff disables
RTG_REPEAT = $14       ; [1:0] horizontal, [3:2] vertical, encoded factor-1
RTG_STRIDE = $16       ; explicit source stride in 16-byte bursts
RTG_VIEW_HSTART = $18  ; viewport bounds in 16 output pixels/lines
RTG_VIEW_HSTOP = $1a   ; stop is exclusive
RTG_VIEW_VSTART = $1c
RTG_VIEW_VSTOP = $1e
RTG_ROW_BURSTS = $20   ; visible source row length in 16-byte bursts


; Build-time physical raster. Define RTG_720P for 1280x720; default is
; 1024x768. HDMI, RTG scanout, the board PLL and constraints must match.
; The driver describes these timings to P96; it cannot program the PLL.
	IFD	RTG_720P
RTG_WIDTH EQU 1280
RTG_HEIGHT EQU 720
RTG_HTOTAL EQU 1650
RTG_VTOTAL EQU 750
RTG_PIXEL_CLOCK EQU 74250000
RTG_HSTART EQU 110
RTG_HSIZE EQU 40
RTG_VSTART EQU 5
RTG_VSIZE EQU 5
	ELSE
RTG_WIDTH EQU 1024
RTG_HEIGHT EQU 768
RTG_HTOTAL EQU 1344
RTG_VTOTAL EQU 806
RTG_PIXEL_CLOCK EQU 66000000
RTG_HSTART EQU 24
RTG_HSIZE EQU 136
RTG_VSTART EQU 3
RTG_VSIZE EQU 6
	ENDC

; Keep a sensible minimum so each indexed row meets the fixed FIFO prefill
; target after ModeRepeat selects the largest fitting horizontal factor.
RTG_MIN_WIDTH EQU 320
RTG_MIN_HEIGHT EQU 192

RTG_HALF_WIDTH EQU RTG_WIDTH/2
; Logical canvases are aligned down to 16 source pixels. The driver owns
; these limits; RTG hardware only follows its programmed viewport and pitch.
RTG_THIRD_WIDTH EQU (RTG_WIDTH/48)*16
RTG_QUARTER_WIDTH EQU (RTG_WIDTH/64)*16
RTG_HALF_HEIGHT EQU (RTG_HEIGHT/32)*16
RTG_THIRD_HEIGHT EQU (RTG_HEIGHT/48)*16
RTG_THIRD_BORDER EQU ((RTG_WIDTH-RTG_THIRD_WIDTH*3)/32)*16
RTG_QUARTER_BORDER EQU ((RTG_WIDTH-RTG_QUARTER_WIDTH*4)/32)*16

; Define RTG_DEBUG at assembly time to include serial logging.
	; Write to serial console
BUG MACRO
	IFD	RTG_DEBUG

	ifnc	"","\9"
	move.l	\9,-(sp)
	endc
	ifnc	"","\8"
	move.l	\8,-(sp)
	endc
	ifnc	"","\7"
	move.l	\7,-(sp)
	endc
	ifnc	"","\6"
	move.l	\6,-(sp)
	endc
	ifnc	"","\5"
	move.l	\5,-(sp)
	endc
	ifnc	"","\4"
	move.l	\4,-(sp)
	endc
	ifnc	"","\3"
	move.l	\3,-(sp)
	endc
	ifnc	"","\2"
	move.l	\2,-(sp)
	endc

	jsr	bugprintf

	dc.b	\1,$d,$a,0
	even

	adda.w	#(NARG-1)*4,sp

	ENDC
	ENDM

MEMORY_SIZE EQU (4<<20)
RTG_RGB_FORMATS EQU (RGBFF_CLUT|RGBFF_R5G6B5|RGBFF_R5G5B5)


;------------------------------------------------------------------------------
ProgStart:
;------------------------------------------------------------------------------

	moveq	#-1,d0
	rts

	IFD	RTG_DEBUG
	bra.b	_bugprintf_end
bugprintf:
		movem.l d0-d1/a0-a3/a6,-(sp)
		move.l	$4.w,a6
		move.l	28(sp),a0
		lea	32(sp),a1
		lea	.putch(pc),a2
		move.l	a6,a3
		jsr	-522(a6)                ; _LVORawDoFmt

.skip		move.l	28(sp),a0
.end:		move.b	(a0)+,d0
		bne.b	.end
		move.l	a0,d0
		addq.l	#1,d0
		and.l	#$fffffffe,d0
		move.l	d0,28(sp)
		movem.l (sp)+,d0-d1/a0-a3/a6
		rts

.putch:
		move.l	a6,-(sp)
		move.l	a3,a6
		jsr	-516(a6)                ; _LVORawPutChar (execPrivate9)
		move.l (sp)+,a6
_bugprintf_end:
	rts
	ENDC

;------------------------------------------------------------------------------
RomTag:
;------------------------------------------------------------------------------

	dc.w	RTC_MATCHWORD
	dc.l	RomTag
	dc.l	ProgEnd
	dc.b	RTF_AUTOINIT	;RT_FLAGS
	dc.b	1		;RT_VERSION
	dc.b	NT_LIBRARY	;RT_TYPE
	dc.b	0		;RT_PRI
	dc.l	MinimigCard
	dc.l	IDString
	dc.l	InitTable
CardName:
	dc.b	'Minimig',0
MinimigCard:
	dc.b	'minimig.card',0,0
	dc.b	'$VER: '
IDString:
	dc.b	'minimig.card 1.15 (19.10.2026)',0
	dc.b	0
expansionLibName:
	dc.b	'expansion.library',0
	cnop	0,4

InitTable:
	dc.l	card_SIZEOF	;DataSize
	dc.l	FuncTable	;FunctionTable
	dc.l	DataTable	;DataTable
	dc.l	InitRoutine
FuncTable:
	dc.l	Open
	dc.l	Close
	dc.l	Expunge
	dc.l	ExtFunc
	dc.l	FindCard
	dc.l	InitCard
	dc.l	-1
DataTable:
	INITBYTE	LN_TYPE,NT_LIBRARY
	INITBYTE	LN_PRI,206
	INITLONG	LN_NAME,MinimigCard
	INITBYTE	LIB_FLAGS,LIBF_SUMUSED|LIBF_CHANGED
	INITWORD	LIB_VERSION,1
	INITWORD	LIB_REVISION,15
	INITLONG	LIB_IDSTRING,IDString
	INITLONG	card_Name,CardName
	dc.w		0,0

;------------------------------------------------------------------------------
InitRoutine:
;------------------------------------------------------------------------------


	movem.l a5,-(sp)
	movea.l d0,a5
	move.l	a6,card_ExecBase(a5)
	move.l	a0,card_SegmentList(a5)
	lea	expansionLibName(pc),a1
	moveq	#0,d0
	jsr	_LVOOpenLibrary(a6)

	move.l	d0,card_ExpansionBase(a5)
	bne.s	.exit

.fail
	movem.l d7/a5/a6,-(sp)
	move.l	#(AT_Recovery|AG_OpenLib|AO_ExpansionLib),d7
	movea.l $4.w,a6
	jsr	_LVOAlert(a6)

	movem.l (sp)+,d7/a5/a6
.exit:
	move.l	a5,d0
	movem.l (sp)+,a5
	rts

;------------------------------------------------------------------------------
Open:
;------------------------------------------------------------------------------

	addq.w	#1,LIB_OPENCNT(a6)
	bclr	#3,card_Flags(a6)




	move.l	a6,d0
	rts

;------------------------------------------------------------------------------
Close:
;------------------------------------------------------------------------------

	moveq	#0,d0
	subq.w	#1,LIB_OPENCNT(a6)
	bne.b	.exit

	btst	#3,card_Flags(a6)
	beq.b	.exit

	bsr.b	Expunge

.exit:
	rts

;------------------------------------------------------------------------------
Expunge:
;------------------------------------------------------------------------------

	movem.l d2/a5/a6,-(sp)
	movea.l a6,a5
	movea.l card_ExecBase(a5),a6
	tst.w	LIB_OPENCNT(a5)
	beq.b	.remove

	bset	#3,card_Flags(a5)
	moveq	#0,d0
	bra.b	.exit

.remove:
	move.l	card_SegmentList(a5),d2
	movea.l a5,a1
	jsr	_LVORemove(a6)

	movea.l card_ExpansionBase(a5),a1
	jsr	_LVOCloseLibrary(a6)

	moveq	#0,d0
	movea.l a5,a1
	move.w	LIB_NEGSIZE(a5),d0
	suba.l	d0,a1
	add.w	LIB_POSSIZE(a5),d0
	jsr	_LVOFreeMem(a6)

	move.l	d2,d0
.exit:
	movem.l (sp)+,d2/a5/a6
	rts

;------------------------------------------------------------------------------
ExtFunc:
;------------------------------------------------------------------------------

	moveq	#0,d0
	rts


;------------------------------------------------------------------------------
FindCard:
;------------------------------------------------------------------------------
;  BOOL FindCard(struct BoardInfo *bi)
;

;  FindCard is called in the first stage of the board initialisation and
;  configuration and is used to look if there is a free and unconfigured
;  board of the type the driver is capable of managing. If it finds one,
;  it immediately reserves it for use by Picasso96, usually by clearing
;  the CDB_CONFIGME bit in the flags field of the ConfigDev struct of
;  this expansion card. But this is only a common example, a driver can
;  do whatever it wants to mark this card as used by the driver. This
;  mechanism is intended to ensure that a board is only configured and
;  used by one driver. FindBoard also usually fills some fields of the
;  BoardInfo struct supplied by the caller, the rtg.library, for example
;  the MemoryBase, MemorySize and RegisterBase fields.

	movem.l a2/a3/a6,-(sp)
	movea.l a0,a2

	move.l	#0,gbi_MemoryBase(a2)
	move.l	#0,gbi_MemorySize(a2)
	move.l	#$b80100,(gbi_RegisterBase,a2)

	moveq	#0,d0
	move.w	$b8010e,d1
	and.w	#$fff0,d1
	cmp.w	#$8320,d1   ; Is this the Chameleon/MiST RTG implementation?
	beq	.compat
	cmp.w	#$8321,d1
	bne	.exit

.compat
	; Earlier Minimig hardware returns its ID for every unused register.
	; Require the HDMI status register before using the new polling/IRQ path.
	move.w  $b8010c,d1
	and.w   #$fff0,d1
	bne     .exit
	move.l	$4,a6	; Do we have any 24-bit Fast RAM?
			; (This is the easiest way to ensure the FB's not in bank 0)
	move.l	#MEMF_24BITDMA|MEMF_FAST,d1
	jsr _LVOAvailMem(a6)
	cmp.l	#$1c0000,d0 ; Can't use $C00000 RAM, so make sure we have more than 1.75 megs
	bgt .ok   ; Bail out if not.
	moveq	#0,d0
	bra .exit

.ok
	moveq	#-1,d0
.exit:
	movem.l (sp)+,a2/a3/a6
	rts



GetVideoMemory:
	move.l  a0,-(a7)
	move.l  #MEMORY_SIZE,d0

.outerloop
	move.l  (a1)+,d1
	beq .done
	BUG "Tooltype %s",d1
	move.l  d1,a0
	moveq   #0,d1
	lea .tooltype,a2

.innerloop
	move.b  (a2)+,d2
	beq .match
.skipspaces
	move.b  (a0)+,d1
	cmp.b   #$20,d1
	beq .skipspaces
	and.b   #$df,d1
	cmp.b d1,d2
	beq .innerloop
	bra .outerloop

.match
	move.b  (a0)+,d1
	cmp.b   #$20,d1
	beq .match

	BUG "match %ld",d1

	sub.b   #$30,d1
	cmp.b #1,d1
	blt .done
	cmp.b #7,d1
	bgt .done
	move.l d1,d0
	swap    d0
	lsl.l   #4,d0
	BUG "memory %ld",d0
.done
	move.l  (a7)+,a0
	rts
.tooltype
	dc.b   "VIDEOMEMORY",$1d,0

	even

;------------------------------------------------------------------------------
InitCard:
;------------------------------------------------------------------------------
;  a0:	struct BoardInfo

	movem.l a2/a5/a6,-(sp)

	bsr GetVideoMemory

	movea.l a0,a2

.allocloop
	move.l	d0,gbi_MemorySize(a2)

	move.l	$4.w,a6
	addi.l	#$00001FF,d0		; add 512 bytes-1
	move.l	#MEMF_24BITDMA|MEMF_FAST|MEMF_REVERSE,d1	; Try $200000 RAM first
	jsr	_LVOAllocMem(a6)

	tst.l	d0
	bne.b	.ok

	move.l	gbi_MemorySize(a2),d0
	lsr.l	#1,d0	; Keep halving the size until alloc succeeds.
	bne .allocloop
	bra .exit

.ok
	addi.l	#$000001FF,d0		; add 512-1
	andi.l	#$FFFFFE00,d0		; and with ~(512-1) to align memory
	move.l	d0,gbi_MemoryBase(a2)


	lea	CardName(pc),a1
	move.l	a1,gbi_BoardName(a2)
	move.l	#10,gbi_BoardType(a2)
	move.l	#0,gbi_GraphicsControllerType(a2)
	move.l	#0,gbi_PaletteChipType(a2)

	move.w	#RTG_RGB_FORMATS,gbi_RGBFormats(a2)

	move.w	#8,gbi_BitsPerCannon(a2)
	move.l	gbi_MemorySize(a2),d0
	sub.l	#$4000,d0
	move.l	d0,gbi_MemorySpaceSize(a2)
	move.l	gbi_MemoryBase(a2),d0
	move.l	d0,gbi_MemorySpaceBase(a2)
	add.l	gbi_MemorySpaceSize(a2),d0
	move.l	d0,gbi_MouseSaveBuffer(a2)

	ori.l	#BIF_INDISPLAYCHAIN,gbi_Flags(a2)
	ori.l	#BIF_VGASCREENSPLIT,gbi_Flags(a2)
	ori.l	#BIF_GRANTDIRECTACCESS,gbi_Flags(a2)

	lea	SetSwitch(pc),a1
	move.l	a1,gbi_SetSwitch(a2)
	lea	SetDAC(pc),a1
	move.l	a1,gbi_SetDAC(a2)
	lea	SetGC(pc),a1
	move.l	a1,gbi_SetGC(a2)
	lea	SetPanning(pc),a1
	move.l	a1,gbi_SetPanning(a2)
	lea	CalculateBytesPerRow(pc),a1
	move.l	a1,gbi_CalculateBytesPerRow(a2)
	lea	CalculateMemory(pc),a1
	move.l	a1,gbi_CalculateMemory(a2)
	lea	GetCompatibleFormats(pc),a1
	move.l	a1,gbi_GetCompatibleFormats(a2)
	lea	SetColorArray(pc),a1
	move.l	a1,gbi_SetColorArray(a2)
	lea	SetDPMSLevel(pc),a1
	move.l	a1,gbi_SetDPMSLevel(a2)
	lea	SetDisplay(pc),a1
	move.l	a1,gbi_SetDisplay(a2)
	lea	SetMemoryMode(pc),a1
	move.l	a1,gbi_SetMemoryMode(a2)
	lea	SetWriteMask(pc),a1
	move.l	a1,gbi_SetWriteMask(a2)
	lea	SetReadPlane(pc),a1
	move.l	a1,gbi_SetReadPlane(a2)
	lea	SetClearMask(pc),a1
	move.l	a1,gbi_SetClearMask(a2)
	lea	WaitVerticalSync(pc),a1
	move.l	a1,gbi_WaitVerticalSync(a2)
	lea	(GetVSyncState,pc),a1
	move.l	a1,(gbi_GetVSyncState,a2)
	lea	SetClock(pc),a1
	move.l	a1,gbi_SetClock(a2)
	lea	ResolvePixelClock(pc),a1
	move.l	a1,gbi_ResolvePixelClock(a2)
	lea	GetPixelClock(pc),a1
	move.l	a1,gbi_GetPixelClock(a2)

	lea	SetSplitPosition(pc),a1
	move.l	a1,gbi_SetSplitPosition(a2)



	move.l	#113440000,gbi_MemoryClock(a2)

	move.l	#0,(gbi_PixelClockCount+0,a2)
	move.l	#12,(gbi_PixelClockCount+4,a2)
	move.l	#12,(gbi_PixelClockCount+8,a2)
	move.l	#0,(gbi_PixelClockCount+12,a2)
	move.l	#0,(gbi_PixelClockCount+16,a2)
;- Planar
;- Chunky
;- HiColor
;- Truecolor
;- Truecolor + Alpha

	move.w	#0,(gbi_MaxHorValue+0,a2)
	move.w	#0,(gbi_MaxVerValue+0,a2)
	move.w	#4095,(gbi_MaxHorValue+2,a2)
	move.w	#4095,(gbi_MaxVerValue+2,a2)
	move.w	#4095,(gbi_MaxHorValue+4,a2)
	move.w	#4095,(gbi_MaxVerValue+4,a2)
	move.w	#0,(gbi_MaxHorValue+6,a2)
	move.w	#0,(gbi_MaxVerValue+6,a2)
	move.w	#0,(gbi_MaxHorValue+8,a2)
	move.w	#0,(gbi_MaxVerValue+8,a2)

	move.w	#0,(gbi_MaxHorResolution+0,a2)
	move.w	#0,(gbi_MaxVerResolution+0,a2)
; Resolution limits follow the selected build-time raster. Keep the
; raster constants, RepeatClocks and FPGA timing consistent when adding profiles.
	move.w	#RTG_WIDTH,(gbi_MaxHorResolution+2,a2)
	move.w	#RTG_HEIGHT,(gbi_MaxVerResolution+2,a2)
	move.w	#RTG_WIDTH,(gbi_MaxHorResolution+4,a2)
	move.w	#RTG_HEIGHT,(gbi_MaxVerResolution+4,a2)
	move.w	#0,(gbi_MaxHorResolution+6,a2)
	move.w	#0,(gbi_MaxVerResolution+6,a2)
	move.w	#0,(gbi_MaxHorResolution+8,a2)
	move.w	#0,(gbi_MaxVerResolution+8,a2)

	move.w	#0,(CardData_IntEnabled,a2)
	clr.w   CardData_ModeValid(a2)
	move.w  #1,CardData_VRepeat(a2)
	clr.w   CardData_VOrigin(a2)
	clr.w   CardData_VStop(a2)
	clr.w   CardData_SourceWidth(a2)
	movea.l gbi_RegisterBase(a2),a1
	clr.w   gbi_MoniSwitch(a2)
	clr.w   RTG_DISPLAY_SWITCH(a1) ; native until explicitly selected
	clr.w   RTG_REPEAT(a1)
	clr.w   RTG_STRIDE(a1)
	move.w  #$7ff,RTG_SPLIT_ROW(a1)
	move.w  #2,RTG_IRQ_CONTROL(a1) ; disable and clear stale IRQ
	lea	gbi_HardInterrupt(a2),a1
	lea	VBL_ISR(pc),a0
	move.l	a0,IS_CODE(a1)
	move.l  a2,IS_DATA(a1)
	moveq	#INTB_PORTS,d0
	move.l	$4,a6
	jsr	_LVOAddIntServer(a6)

	; Matching core supplies HDMI frame interrupts even while native is selected.
	ori.l   #(1<<4),gbi_Flags(a2)    ; BIF_VBLANKINTERRUPT
	lea	SetInterrupt(pc),a1
	move.l	a1,gbi_SetInterrupt(a2)



	ori.l	#(1<<3),gbi_Flags(a2)        ; BIF_CACHEMODECHANGE
	move.l	gbi_MemoryBase(a2),gbi_MemorySpaceBase(a2)
	move.l	gbi_MemorySize(a2),gbi_MemorySpaceSize(a2)

	moveq	#-1,d0
.exit:
	movem.l (sp)+,a2/a5/a6
	rts

;------------------------------------------------------------------------------
SetSwitch:
; a0: BoardInfo, d0.w: requested display. Return the previous switch state.
	movem.l d1/a1,-(sp)
	BUG "SetSwitch %ld",d0
	move.w gbi_MoniSwitch(a0),d1
	andi.w #1,d0
	tst.w CardData_ModeValid(a0)
	bne.s .valid_mode
	moveq #0,d0
.valid_mode:
	move.w d0,gbi_MoniSwitch(a0)
	movea.l gbi_RegisterBase(a0),a1
	move.w d0,RTG_DISPLAY_SWITCH(a1)
	move.w d1,d0
	andi.l #1,d0
	movem.l (sp)+,d1/a1
	rts

;------------------------------------------------------------------------------
SetDAC:
;------------------------------------------------------------------------------
;  a0: struct BoardInfo
;  d7: RGBFTYPE RGBFormat
;  This function is called whenever the RGB format of the display changes,
;  e.g. from chunky to TrueColor. Usually, all you have to do is to set
;  the RAMDAC of your board accordingly.

; Indexed/16-bit format and RGB555/RGB565 selection; pixel clock is fixed.
	moveq	#1,d0
	cmp.l	#RGBFB_R5G6B5,d7
	beq	.16bit
	moveq	#2,d0
.16bit
	move.l	(gbi_RegisterBase,a0),a1
	move.w	d0,(6,a1)
	moveq #0,d0
	cmp.l #RGBFB_CLUT,d7
	bne.s .store_format
	move.w #$8000,d0
.store_format:
	move.w d0,(4,a1)
	bsr ProgramRowLength
.done
	rts

;------------------------------------------------------------------------------
SetGC:
; a0: BoardInfo, a1: ModeInfo, d0: border, d7: RGB format.
; Physical HDMI timing stays fixed. Geometry is prepared here, not in scanout.
	move.l a1,gbi_ModeInfo(a0)
	move.w d0,gbi_Border(a0)
	movem.l d1-d4/a1,-(sp)
	bsr ModeRepeat
	movea.l gbi_RegisterBase(a0),a1
	clr.w CardData_ModeValid(a0)
	tst.l d0
	bmi .invalid
	move.w #1,CardData_ModeValid(a0)
	move.w d0,RTG_REPEAT(a1)
	move.w d0,d4
	andi.w #3,d4
	addq.w #1,d4
	lsr.w #2,d0
	addq.w #1,d0
	move.w d0,CardData_VRepeat(a0)

	movea.l gbi_ModeInfo(a0),a1
	moveq #0,d2
	move.w gmi_Width(a1),d2
	andi.w #$fff0,d2
	move.w d2,CardData_SourceWidth(a0)
	mulu.w d4,d2
	moveq #0,d3
	move.w gmi_Height(a1),d3
	andi.w #$fff0,d3
	mulu.w d0,d3
	movea.l gbi_RegisterBase(a0),a1

; Center to the nearest lower 16-pixel boundary. Any unmatched border block
; stays at the right/bottom. Source cropping never changes the bitmap stride.
	move.w #RTG_WIDTH,d4
	sub.w d2,d4
	lsr.w #5,d4
	move.w d4,RTG_VIEW_HSTART(a1)
	lsr.w #4,d2
	add.w d4,d2
	move.w d2,RTG_VIEW_HSTOP(a1)
	move.w #RTG_HEIGHT,d4
	sub.w d3,d4
	lsr.w #5,d4
	move.w d4,RTG_VIEW_VSTART(a1)
	lsl.w #4,d4
	move.w d4,CardData_VOrigin(a0)
	add.w d4,d3
	move.w d3,CardData_VStop(a0)
	lsr.w #4,d3
	move.w d3,RTG_VIEW_VSTOP(a1)
	bsr ProgramRowLength
; Seed the full bitmap pitch, including pixels cropped from the viewport.
; SetPanning may later replace this with a larger virtual bitmap pitch.
	movea.l gbi_ModeInfo(a0),a1
	moveq #0,d0
	move.w gmi_Width(a1),d0
	bsr CalculateBytesPerRow
	lsr.w #4,d0
	movea.l gbi_RegisterBase(a0),a1
	move.w d0,RTG_STRIDE(a1)
	move.w gbi_YSplit(a0),d0
	bsr SetSplitPosition
	bra.s .done
.invalid:
	clr.w RTG_DISPLAY_SWITCH(a1)
	clr.w gbi_MoniSwitch(a0)
.done:
	movem.l (sp)+,d1-d4/a1
	rts

; Source width is independent of pitch and output repetition. SetDAC may run
; before or after SetGC, so both callbacks update this inexpensive register.
ProgramRowLength:
	move.w CardData_SourceWidth(a0),d0
	lsr.w #3,d0
	cmpi.l #RGBFB_CLUT,d7
	bne.s .store
	lsr.w #1,d0
.store:
	movea.l gbi_RegisterBase(a0),a1
	move.w d0,RTG_ROW_BURSTS(a1)
	rts

; a1: ModeInfo. Return d0=repeat encoding, d1=logical clock index, or d0=-1.
; All visible source dimensions are rounded down to 16 pixels. This lets the
; core omit low coordinate bits; nonaligned modes retain their full byte pitch.
ModeRepeat:
	movem.l d2/d3,-(sp)
	moveq #0,d0
	moveq #0,d1
	moveq #0,d2
	moveq #0,d3
	move.w gmi_Width(a1),d2
	move.w gmi_Height(a1),d3
	cmpi.w #RTG_WIDTH,d2
	bhi.s .invalid
	cmpi.w #RTG_HEIGHT,d3
	bhi.s .invalid
	andi.w #$fff0,d2
	cmpi.w #RTG_MIN_WIDTH,d2
	bcs.s .invalid
	andi.w #$fff0,d3
	cmpi.w #RTG_MIN_HEIGHT,d3
	bcs.s .invalid
	cmpi.w #RTG_HALF_WIDTH,d2
	bhi.s .height
	moveq #1,d0
	cmpi.w #RTG_THIRD_WIDTH,d2
	bhi.s .height
	moveq #2,d0
	cmpi.w #RTG_QUARTER_WIDTH,d2
	bhi.s .height
	moveq #3,d0
.height:
	cmpi.w #RTG_HALF_HEIGHT,d3
	bhi.s .done
	ori.w #4,d0
	cmpi.w #RTG_THIRD_HEIGHT,d3
	bhi.s .done
	addi.w #4,d0
.done:
	move.w d0,d1
	bra.s .return
.invalid:
	moveq #-1,d0
.return:
	movem.l (sp)+,d2/d3
	rts

;------------------------------------------------------------------------------
SetPanning:
;------------------------------------------------------------------------------
;  a0: struct BoardInfo
;  a1: UBYTE* Memory
;  d0: WORD Width
;  d1: WORD XOffset
;  d2: WORD YOffset
;  d7: RGBFTYPE RGBFormat
;  This function sets the view origin of a display which might also be
;  overscanned. In register a1 you get the start address of the screen
;  bitmap on the Amiga side. You will have to subtract the starting
;  address of the board memory from that value to get the memory start
;  offset within the board. Then you get the offset in pixels of the
;  left upper edge of the visible part of an overscanned display. From
;  these values you will have to calculate the LinearStartingAddress
;  fields of the CRTC registers.

;  On Minimig we simply set the start address.
;  and also set the card start address for screen dragging
	BUG "SetPanning %ld, %ld, %ld, %ld, %ld\n",a1,d1,d2,d0,d7
	tst.w CardData_ModeValid(a0)
	beq .done
	move.w	d1,(gbi_XOffset,a0)
	move.w	d2,(gbi_YOffset,a0)

	bsr	CalculateBytesPerRow	; Only trashes d0 and d1
	move.l a2,-(sp)
	movea.l gbi_RegisterBase(a0),a2
	move.w d0,d1
	lsr.w #4,d1
	move.w d1,RTG_STRIDE(a2)
	movea.l (sp)+,a2
	mulu	d0,d2
	add.l	d2,a1

	move.l	a1,d0
	move.l	d0,d1
	and.l	#$00ffffff,d1
	and.l	#$ff000000,d0
	beq	.skip
	or.l	#$1000000,d1
.skip

	movea.l gbi_RegisterBase(a0),a1
	move.l	d1,(a1)

	move.l	gbi_MemoryBase(a0),d0
	move.l	d0,d1
	and.l	#$00ffffff,d1
	and.l	#$ff000000,d0
	beq	.skip2
	or.l	#$1000000,d1
.skip2
	move.l	d1,(8,a1)
.done:
	rts


;------------------------------------------------------------------------------
CalculateBytesPerRow:
;------------------------------------------------------------------------------
;  a0:	struct BoardInfo
;  d0:	uae_u16 Width
;  d7:	RGBFTYPE RGBFormat
;  This function calculates the amount of bytes needed for a line of
;  "Width" pixels in the given RGBFormat.

	; Offscreen bitmaps use their actual width, without expanding to a mode.
	cmpi.l	#RGBFB_CLUT,d7
	beq.s	.align
	cmpi.l	#RGBFB_R5G6B5,d7
	beq.s	.direct
	cmpi.l	#RGBFB_R5G5B5,d7
	bne.s	.unsupported
.direct:
	add.w	d0,d0
.align:
	; Each source row starts on the SDRAM's 16-byte burst boundary.
	addi.w	#15,d0
	andi.w	#$fff0,d0
	rts
.unsupported:
	moveq	#0,d0
	rts

;------------------------------------------------------------------------------
CalculateMemory:
;------------------------------------------------------------------------------

	move.l	a1,d0
	rts

;------------------------------------------------------------------------------
SetColorArray:
;------------------------------------------------------------------------------
;  a0: struct BoardInfo
;  d0.w: startindex
;  d1.w: count
;  when this function is called, your driver has to fetch "count" color
;  values starting at "startindex" from the CLUT field of the BoardInfo
;  structure and write them to the hardware. The color values are always
;  between 0 and 255 for each component regardless of the number of bits
;  per cannon your board has. So you might have to shift the colors
;  before writing them to the hardware.


	lea	gbi_CLUT(a0),a1
	movea.l gbi_RegisterBase(a0),a0

	lea	(a1,d0.w),a1
	lea	(a1,d0.w*2),a1
	adda.l	#$300,a0
	lea	(a0,d0.w*4),a0

	bra.b	.sla_loop_end

.sla_loop:
	moveq	#0,d0
	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.b	(a1)+,d0
	lsl.l	#8,d0
	move.b	(a1)+,d0

	move.l	d0,(a0)+
.sla_loop_end
	dbra	d1,.sla_loop

	rts

;------------------------------------------------------------------------------
SetDPMSLevel:
;------------------------------------------------------------------------------

	rts

;------------------------------------------------------------------------------
SetDisplay:
;------------------------------------------------------------------------------
;  a0:	struct BoardInfo
;  d0:	BOOL state
;  This function enables and disables the video display.
;
;  NOTE: return the opposite of the state

	BUG "SetDisplay %ld",d0
	not.b	d0
	andi.w	#1,d0
	rts

;------------------------------------------------------------------------------
SetMemoryMode:
;------------------------------------------------------------------------------

	rts

;------------------------------------------------------------------------------
SetWriteMask:
;------------------------------------------------------------------------------

	rts

;------------------------------------------------------------------------------
SetReadPlane:
;------------------------------------------------------------------------------

	rts

;------------------------------------------------------------------------------
SetClearMask:
;------------------------------------------------------------------------------

	move.b	d0,gbi_ClearMask(a0)
	rts

;------------------------------------------------------------------------------
WaitVerticalSync:
; a0: BoardInfo, d0: FALSE waits for blank start, TRUE waits for blank end.
; Inactive scanout returns immediately, including during a clock switch.
	movem.l d1/a1,-(sp)
	movea.l gbi_RegisterBase(a0),a1
	tst.w   d0
	bne.s   .wait_end
.wait_start:
	move.w  RTG_STATUS(a1),d1
	btst    #3,d1
	beq.s   .done
	btst    #0,d1
	beq.s   .wait_start
	bra.s   .done
.wait_end:
	move.w  RTG_STATUS(a1),d1
	btst    #3,d1
	beq.s   .done
	btst    #0,d1
	bne.s   .wait_end
.done:
	movem.l (sp)+,d1/a1
	rts

;------------------------------------------------------------------------------
GetVSyncState:
; Report HDMI blanking rather than the independent Amiga beam position.
	movea.l gbi_RegisterBase(a0),a1
	move.w  RTG_STATUS(a1),d0
	and.l   #1,d0
	rts

;------------------------------------------------------------------------------
SetClock:
; The physical HDMI clock is fixed; this required callback has no work to do.
	rts

;------------------------------------------------------------------------------
ResolvePixelClock:
; Logical clocks describe scaled modes; the physical clock is fixed per build.
; a1: ModeInfo. Always return a nonzero clock, including editor placeholders.
	movem.l d1/d2,-(sp)
	bsr ModeRepeat
	tst.l d0
	bmi .invalid
	move.l RepeatClocks(pc,d1.l*4),gmi_PixelClock(a1)
	clr.w gmi_Clock(a1)
	move.b d1,gmi_Clock(a1)
	andi.w #3,d0
	move.w RepeatHTotal(pc,d0.w*2),d2
	move.w d2,gmi_HorTotal(a1)
	sub.w gmi_Width(a1),d2
	move.w d2,gmi_HorBlankSize(a1)
	move.w RepeatCanvasWidth(pc,d0.w*2),d2
	sub.w gmi_Width(a1),d2
	add.w RepeatHStart(pc,d0.w*2),d2
	move.w d2,gmi_HorSyncStart(a1)
	move.w RepeatHSize(pc,d0.w*2),gmi_HorSyncSize(a1)
	move.w d1,d0
	lsr.w #2,d0
	move.w RepeatVTotal(pc,d0.w*2),d2
	move.w d2,gmi_VerTotal(a1)
	sub.w gmi_Height(a1),d2
	move.w d2,gmi_VerBlankSize(a1)
	move.w RepeatCanvasHeight(pc,d0.w*2),d2
	sub.w gmi_Height(a1),d2
	add.w RepeatVStart(pc,d0.w*2),d2
	move.w d2,gmi_VerSyncStart(a1)
	move.w RepeatVSize(pc,d0.w*2),gmi_VerSyncSize(a1)
	move.l d1,d0
	bra.s .done
.invalid:
	; Mode editing may temporarily pass zero or out-of-range dimensions.
	; Keep its clock/timing arithmetic defined, while SetGC rejects scanout.
	move.l #RTG_PIXEL_CLOCK,gmi_PixelClock(a1)
	clr.w gmi_Clock(a1)
	move.w #RTG_HTOTAL,gmi_HorTotal(a1)
	move.w #(RTG_HTOTAL-RTG_WIDTH),gmi_HorBlankSize(a1)
	move.w #RTG_HSTART,gmi_HorSyncStart(a1)
	move.w #RTG_HSIZE,gmi_HorSyncSize(a1)
	move.w #RTG_VTOTAL,gmi_VerTotal(a1)
	move.w #(RTG_VTOTAL-RTG_HEIGHT),gmi_VerBlankSize(a1)
	move.w #RTG_VSTART,gmi_VerSyncStart(a1)
	move.w #RTG_VSIZE,gmi_VerSyncSize(a1)
	moveq #0,d0
.done:
	movem.l (sp)+,d1/d2
	rts

;------------------------------------------------------------------------------
GetPixelClock:
; d0: index, d7: RGB format. Return logical frequency and bytes/source pixel.
	moveq #0,d1
	cmp.l #RGBFB_CLUT,d7
	beq.s .indexed
	cmp.l #RGBFB_R5G6B5,d7
	beq.s .direct
	cmp.l #RGBFB_R5G5B5,d7
	beq.s .direct
.invalid:
	moveq #0,d0
	rts
.indexed:
	moveq #1,d1
	bra.s .clock
.direct:
	moveq #2,d1
.clock:
	cmpi.l #12,d0
	bcc.s .invalid
	move.l RepeatClocks(pc,d0.l*4),d0
	rts

; Clock = physical pixel clock * logical HTotal * logical VTotal /
; (physical HTotal * physical VTotal), rounded to the nearest integer Hz.
; Entries are grouped by vertical factor, then horizontal factor. The default
; raster's 3x vertical total rounds to 269, so its clocks include that rounding.
; PixelClockCount is twelve: four horizontal by three vertical factors.
RepeatClocks:
	IFD RTG_720P
	dc.l 74250000,37125000,24750000,18585000
	dc.l 37125000,18562500,12375000,9292500
	dc.l 24750000,12375000,8250000,6195000
	ELSE
	dc.l 66000000,33000000,22000000,16500000
	dc.l 33000000,16500000,11000000,8250000
	dc.l 22027295,11013648,7342432,5506824
	ENDC
RepeatCanvasWidth:
	dc.w RTG_WIDTH,RTG_HALF_WIDTH,RTG_THIRD_WIDTH,RTG_QUARTER_WIDTH
RepeatCanvasHeight:
	dc.w RTG_HEIGHT,RTG_HALF_HEIGHT,RTG_THIRD_HEIGHT
RepeatHTotal:
	dc.w RTG_HTOTAL,(RTG_HTOTAL+1)/2,(RTG_HTOTAL+2)/3,(RTG_HTOTAL+3)/4
RepeatHStart:
	dc.w RTG_HSTART,(RTG_HSTART+1)/2,(RTG_HSTART+RTG_THIRD_BORDER+2)/3,(RTG_HSTART+RTG_QUARTER_BORDER+3)/4
RepeatHSize:
	dc.w RTG_HSIZE,RTG_HSIZE/2,RTG_HSIZE/3,RTG_HSIZE/4
RepeatVTotal:
	dc.w RTG_VTOTAL,(RTG_VTOTAL+1)/2,(RTG_VTOTAL+2)/3
RepeatVStart:
	dc.w RTG_VSTART,(RTG_VSTART+1)/2,(RTG_VSTART+2)/3
RepeatVSize:
	dc.w RTG_VSIZE,(RTG_VSIZE+1)/2,(RTG_VSIZE+2)/3

;------------------------------------------------------------------------------
SetInterrupt:
	movem.l d1/a1,-(sp)
	move.w  d0,CardData_IntEnabled(a0)
	movea.l gbi_RegisterBase(a0),a1
	moveq   #2,d1 ; acknowledge and disable
	tst.w   d0
	beq.s   .store
	moveq   #3,d1 ; acknowledge and enable
.store:
	move.w  d1,RTG_IRQ_CONTROL(a1)
	movem.l (sp)+,d1/a1
	rts

;------------------------------------------------------------------------------
VBL_ISR:
; Level-2 PORTS is shared with CIA/Gayle. Check our source before handling it.
	movem.l d1/a0-a1/a6,-(sp)
	movea.l gbi_RegisterBase(a1),a0
	move.w  RTG_STATUS(a0),d1
	btst    #1,d1
	beq.s   .done
	moveq   #2,d1
	tst.w   CardData_IntEnabled(a1)
	beq.s   .ack_only
	moveq   #3,d1
.ack_only:
	move.w  d1,RTG_IRQ_CONTROL(a0)
	move.w  RTG_STATUS(a0),d1 ; finish the hardware acknowledgement
	tst.w   CardData_IntEnabled(a1)
	beq.s   .done
	movea.l gbi_ExecBase(a1),a6
	lea     gbi_SoftInterrupt(a1),a1
	jsr     _LVOCause(a6)
.done:
	movem.l (sp)+,d1/a0-a1/a6
	moveq   #0,d0 ; allow other servers on the shared interrupt to run
	rts

;------------------------------------------------------------------------------
GetCompatibleFormats:
; Supported formats share the same linear memory aperture and may coexist.
	moveq	#0,d0
	cmpi.l	#RGBFB_CLUT,d7
	beq.s	.supported
	cmpi.l	#RGBFB_R5G6B5,d7
	beq.s	.supported
	cmpi.l	#RGBFB_R5G5B5,d7
	bne.s	.done
.supported:
	move.l	#RTG_RGB_FORMATS,d0
.done:
	rts

;==============================================================================

SetSplitPosition:
; a0: BoardInfo, d0: first secondary-framebuffer row; 0 disables dragging.
	move.w d0,gbi_YSplit(a0)
	movea.l gbi_RegisterBase(a0),a1
	tst.w d0
	beq.s .disable
	mulu.w CardData_VRepeat(a0),d0
	moveq #0,d1
	move.w CardData_VOrigin(a0),d1
	add.l d1,d0
	move.w CardData_VStop(a0),d1
	cmp.l d1,d0
	bcs.s .store
.disable:
	move.w #$7ff,d0
.store:
	move.w d0,RTG_SPLIT_ROW(a1)
	rts

ProgEnd:
	end
