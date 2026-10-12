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

	include hardware/custom.i

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

; HDMI-timed RTG registers, relative to $B80100.
RTG_STATUS = $0c       ; read: blank, pending, enabled, active (bits 0..3)
RTG_IRQ_CONTROL = $0c  ; write: enable bit0, acknowledge bit1 (W1C)
RTG_FRAME_SEQUENCE = $10
RTG_DISPLAY_SWITCH = $12 ; read/write bit0: 0 native, 1 RTG
RTG_SPLIT_ROW = $14    ; first secondary-framebuffer row, $7ff disables


debug
;debugbc
;HasBlitter
;blitterhistory
;HasSprite

beacon:
	move.l	#8191,d0
.loop
	move.w	d0,$dff180
	dbf	d0,.loop
	rts

	; Write to a register which we can observe with the 832 firmware
BC MACRO
    IFD debugbc
    move.l  \2,$b80004+4*\1
    ENDC
    ENDM

	; Write to serial console
BUG MACRO
	IFD	debug

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

****************************************************************************
;	section ReplayRTG,code
****************************************************************************

MEMORY_SIZE EQU (4<<20)
MEMF_REPLAY EQU (1<<14)


;------------------------------------------------------------------------------
ProgStart:
;------------------------------------------------------------------------------

	moveq	#-1,d0
	rts

	IFD	debug
	bra.b	_bugprintf_end
bugprintf:
		movem.l d0-d1/a0-a3/a6,-(sp)
		move.l	$4.w,a6
		move.l	28(sp),a0
		lea	32(sp),a1
		lea	.putch(pc),a2
;		 jsr	 beacon
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
	dc.b	'minimig.card 1.8 (12.10.2026)',0
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
	INITWORD	LIB_REVISION,8
	INITLONG	LIB_IDSTRING,IDString
	INITLONG	card_Name,CardName
	dc.w		0,0

;------------------------------------------------------------------------------
InitRoutine:
;------------------------------------------------------------------------------

;	BUG "Minimig.card InitRoutine()"

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



	IFD blitterhistory
	move.l	a0,-(sp)
	lea	$80000,a0
	moveq.l #16,d0
.fill:
	clr.l	(a0)+
	dbra	d0,.fill

	move.l	(sp)+,a0
	ENDC

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
;	 move.l  #MEMORY_SIZE/8,gbi_MemorySize(a2)
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

;	 move.l  $4.w,a6
;	 move.l  #MEMORY_SIZE,d0
;	 addi.l  #$00001FF,d0		 ; add 512 bytes-1
;	 move.l  #MEMF_24BITDMA|MEMF_FAST|MEMF_REVERSE,d1	 ; Try $200000 RAM first
;	 jsr	 _LVOAllocMem(a6)

;	 tst.l	 d0
;	 bne.b	 .ok

;	 move.l  #MEMORY_SIZE,d0
;	 addi.l  #$1ff,d0
;	 move.l  #MEMF_FAST|MEMF_REVERSE,d1
;	 jsr	 _LVOAllocMem(a6)
;	 tst.l	 d0
;	 bne.b	 .ok

;	 ; If allocation failed, try a smaller chunk.
;	 move.l  #MEMORY_SIZE/2,gbi_MemorySize(a2)
;	 move.l  #MEMORY_SIZE/2,d0
;	 addi.l  #$1ff,d0
;	 move.l  #MEMF_24BITDMA|MEMF_FAST|MEMF_REVERSE,d1
;	 jsr	 _LVOAllocMem(a6)
;	 tst.l	 d0
;	 beq.b	 .exit


.ok
;	 addi.l  #$000001FF,d0		 ; add 512-1
;	 andi.l  #$FFFFFE00,d0		 ; and with ~(512-1) to align memory
;	 move.l  d0,gbi_MemoryBase(a2)

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

	moveq	#RGBFF_CLUT,d0
	or.w	#RGBFF_R5G6B5,d0
	or.w	#RGBFF_R5G5B5,d0
	move.w	d0,gbi_RGBFormats(a2)

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


;	 lea	 AllocCardMem(pc),a1
;	 move.l  a1,gbi_AllocCardMem(a2)
;	 lea	 FreeCardMem(pc),a1
;	 move.l  a1,gbi_FreeCardMem(a2)

	move.l	#113440000,gbi_MemoryClock(a2)

	move.l	#0,(gbi_PixelClockCount+0,a2)
	move.l	#1,(gbi_PixelClockCount+4,a2)
	move.l	#1,(gbi_PixelClockCount+8,a2)
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
	move.w	#1024,(gbi_MaxHorResolution+2,a2)
	move.w	#768,(gbi_MaxVerResolution+2,a2)
	move.w	#1024,(gbi_MaxHorResolution+4,a2)
	move.w	#768,(gbi_MaxVerResolution+4,a2)
	move.w	#0,(gbi_MaxHorResolution+6,a2)
	move.w	#0,(gbi_MaxVerResolution+6,a2)
	move.w	#0,(gbi_MaxHorResolution+8,a2)
	move.w	#0,(gbi_MaxVerResolution+8,a2)

	move.w	#0,(CardData_IntEnabled,a2)
    movea.l gbi_RegisterBase(a2),a1
    clr.w   gbi_MoniSwitch(a2)
    clr.w   RTG_DISPLAY_SWITCH(a1) ; native until explicitly selected
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

	ifd	HasBlitter
	ori.l	#(1<<15),gbi_Flags(a2)       ; BIF_BLITTER
	lea	BlitRectNoMaskComplete(pc),a1
	move.l	a1,gbi_BlitRectNoMaskComplete(a2)
	lea	BlitRect(pc),a1
	move.l	a1,gbi_BlitRect(a2)
	lea	WaitBlitter(pc),a1
	move.l	a1,gbi_WaitBlitter(a2)
	ENDC

	ifd	HasSprite
	ori.l	#(1<<0),gbi_Flags(a2)        ; BIF_HARDWARESPRITE
	lea	SetSprite(pc),a1
	move.l	a1,gbi_SetSprite(a2)
	lea	SetSpritePosition(pc),a1
	move.l	a1,gbi_SetSpritePosition(a2)
	lea	SetSpriteImage(pc),a1
	move.l	a1,gbi_SetSpriteImage(a2)
	lea	SetSpriteColor(pc),a1
	move.l	a1,gbi_SetSpriteColor(a2)
	ENDC

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
	cmp.l	#10,d7
	beq	.16bit
	moveq	#2,d0
.16bit
	move.l	(gbi_RegisterBase,a0),a1
	move.w	d0,(6,a1)
    moveq #0,d0
    cmp.l #1,d7
    bne.s .store_format
    move.w #$8000,d0
.store_format:
    move.w d0,(4,a1)
.done
	rts

;------------------------------------------------------------------------------
SetGC:
; a0: BoardInfo, a1: ModeInfo, d0: border. HDMI supplies fixed 1024x768 timing.
    move.l a1,gbi_ModeInfo(a0)
    move.w d0,gbi_Border(a0)
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
	move.w	d1,(gbi_XOffset,a0)
	move.w	d2,(gbi_YOffset,a0)

	bsr	CalculateBytesPerRow	; Only trashes d0 and d1
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

	rts


;------------------------------------------------------------------------------
CalculateBytesPerRow:
;------------------------------------------------------------------------------
;  a0:	struct BoardInfo
;  d0:	uae_u16 Width
;  d7:	RGBFTYPE RGBFormat
;  This function calculates the amount of bytes needed for a line of
;  "Width" pixels in the given RGBFormat.

;	 BUG "BytesPerRow %ld,%ld\n",d0,d7

	cmpi.l	#16,d7
	bcc.b	.exit

	move.w	.base(pc,d7.l*2),d1
	jmp	.base(pc,d1.w)

.base:
	dc.w	.pp_1Bit-.base
	dc.w	.pp_1Byte-.base
	dc.w	.pp_3Bytes-.base
	dc.w	.pp_3Bytes-.base
	dc.w	.pp_2Bytes-.base
	dc.w	.pp_2Bytes-.base
	dc.w	.pp_4Bytes-.base
	dc.w	.pp_4Bytes-.base
	dc.w	.pp_4Bytes-.base
	dc.w	.pp_4Bytes-.base
	dc.w	.pp_2Bytes-.base
	dc.w	.pp_2Bytes-.base
	dc.w	.pp_2Bytes-.base
	dc.w	.pp_2Bytes-.base
	dc.w	.pp_2Bytes-.base
	dc.w	.pp_1Byte-.base

.pp_4Bytes:
	add.w	d0,d0
.pp_2Bytes:
	add.w	d0,d0
	bra.b	.exit

.pp_3Bytes:
	move.w	d0,d1
	add.w	d0,d1
	add.w	d1,d0
	bra.b	.exit

.pp_1Bit:
	lsr.w	#3,d0

.pp_1Byte:

.exit:
;	 add.w	 #31,d0      ; Round up to multiple of 32 pixels
;	 and.w	 #$ffe0,d0
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

;	 BUG	 "SetColorArray ( %ld / %ld )",d0,d1

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
;------------------------------------------------------------------------------

;	For minimig this gets set at the same time as all the other parameters

;	movea.l gbi_ModeInfo(a0),a1
;	movea.l gbi_RegisterBase(a0),a0
;	move.b	gmi_second_union(a1),d0
;	lsl.w	#8,d0
;	move.b	gmi_Clock(a1),d0
;	move.w	d0,VDE_ClockDivider(a0)
;	BUG	"VDE_ClockDivider = %lx",d0
	rts

;------------------------------------------------------------------------------
ResolvePixelClock:
; One fixed HDMI clock. No Agnus/PLL divider programming is required.
; a1: ModeInfo; return d0=clock index 0.
    move.l #66000000,gmi_PixelClock(a1)
    clr.w gmi_Clock(a1)
    moveq #0,d0
    rts

;------------------------------------------------------------------------------
GetPixelClock:
; d0: index, d7: RGB format. Return frequency in d0, bytes/pixel in d1.
    moveq #0,d1
    cmp.l #1,d7
    beq.s .indexed
    cmp.l #10,d7
    beq.s .direct
    cmp.l #11,d7
    beq.s .direct
    moveq #0,d0
    rts
.indexed:
    moveq #1,d1
    bra.s .clock
.direct:
    moveq #2,d1
.clock:
    move.l #66000000,d0
    rts

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
;------------------------------------------------------------------------------
;	 BUG "GCF %lx",d7
	moveq	#-1,d0
	rts


;------------------------------------------------------------------------------
GetBytesPerPixel:
;------------------------------------------------------------------------------
;	 BUG "GBPP %lx",d7
	move.b	.BytesPerPixel(pc,d7.l),d7
	rts

.BytesPerPixel:

	dc.b	1	; RGBFB_NONE
	dc.b	1	; RGBFB_CLUT,
	dc.b	3	; RGBFB_R8G8B8
	dc.b	3	; RGBFB_B8G8R8
	dc.b	2	; RGBFB_R5G6B5PC
	dc.b	2	; RGBFB_R5G5B5PC
	dc.b	4	; RGBFB_A8R8G8B8
	dc.b	4	; RGBFB_A8B8G8R8
	dc.b	4	; RGBFB_R8G8B8A8
	dc.b	4	; RGBFB_B8G8R8A8
	dc.b	2	; RGBFB_R5G6B5
	dc.b	2	; RGBFB_R5G5B5
	dc.b	2	; RGBFB_B5G6R5PC
	dc.b	2	; RGBFB_B5G5R5PC
	dc.b	2	; RGBFB_Y4U2V2
	dc.b	1	; RGBFB_Y4U1V1


;==============================================================================

SetSplitPosition:
; a0: BoardInfo, d0: first secondary-framebuffer row; 0 disables dragging.
    move.w d0,gbi_YSplit(a0)
    movea.l gbi_RegisterBase(a0),a1
    tst.w d0
    bne.s .store
    move.w #$7ff,d0
.store:
    move.w d0,RTG_SPLIT_ROW(a1)
    rts

ProgEnd:
	end
