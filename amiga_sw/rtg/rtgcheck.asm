; Read-only Amiga Shell diagnostic for Minimig P96 board detection.
; No display switching, register writes, framebuffer allocation or IRQ setup.
    machine 68020
    include exec/exec.i
    include exec/memory.i
    include lvo/exec_lib.i
    include lvo/dos_lib.i
    include boardinfo.i

    section code,code
start:
    movem.l d2-d7/a2-a6,-(sp)
    moveq #20,d6
    move.l $4.w,a6
    lea dosname(pc),a1
    moveq #0,d0
    jsr _LVOOpenLibrary(a6)
    tst.l d0
    beq .exit
    move.l d0,a5
    move.l a5,a6
    jsr _LVOOutput(a6)
    move.l d0,d7
    move.l d7,d1
    lea banner(pc),a0
    move.l a0,d2
    move.l #banner_end-banner,d3
    jsr _LVOWrite(a6)

    moveq #0,d0
    move.w $b8010e,d0
    move.l d0,idvalue
    moveq #0,d0
    move.w $b8010c,d0
    move.l d0,statusvalue
    move.l $4.w,a6
    move.l #MEMF_FAST|MEMF_24BITDMA,d1
    jsr _LVOAvailMem(a6)
    move.l d0,freevalue

    ; Open the exact installed file, then call only its FindCard vector.
    ; FindCard only fills BoardInfo and checks registers/available memory.
    lea cardname(pc),a1
    moveq #0,d0
    jsr _LVOOpenLibrary(a6)
    tst.l d0
    beq .report
    move.l d0,a4
    move.l #1,loadedvalue
    moveq #0,d0
    move.w LIB_VERSION(a4),d0
    move.l d0,versionvalue
    move.w LIB_REVISION(a4),d0
    move.l d0,revisionvalue
    move.l a4,a6
    lea board,a0
    jsr -30(a6) ; FindCard: fifth .card library vector
    move.l d0,foundvalue
    move.l $4.w,a6
    move.l a4,a1
    jsr _LVOCloseLibrary(a6)

.report:
    lea report(pc),a0
    lea values,a1
    lea putch(pc),a2
    lea buffer,a3
    move.l $4.w,a6
    jsr _LVORawDoFmt(a6)
    lea buffer,a0
    move.l a0,d2
    moveq #0,d3
.length:
    tst.b (a0)+
    beq .write
    addq.l #1,d3
    bra .length
.write:
    move.l d7,d1
    move.l a5,a6
    jsr _LVOWrite(a6)
    moveq #0,d6
    tst.l foundvalue
    bne .close
    moveq #5,d6
.close:
    move.l $4.w,a6
    move.l a5,a1
    jsr _LVOCloseLibrary(a6)
.exit:
    move.l d6,d0
    movem.l (sp)+,d2-d7/a2-a6
    rts
putch:
    move.b d0,(a3)+
    rts

dosname: dc.b 'dos.library',0
cardname: dc.b 'LIBS:Picasso96/minimig.card',0
banner: dc.b 'Minimig RTG detection check (read-only)',10
banner_end:
report:
    dc.b 'ID $B8010E: $%04lx (expected $8321)',10
    dc.b 'Status $B8010C: $%04lx (upper 12 bits must be zero)',10
    dc.b 'Available 24-bit Fast RAM: %ld bytes',10
    dc.b 'Installed .card opened: %ld (1=yes, 0=no)',10
    dc.b 'Installed .card version: %ld.%ld (expected 1.5)',10
    dc.b 'FindCard returned: $%08lx (FFFFFFFF=yes, 00000000=no)',10,0

    section data,bss
    cnop 0,4
values:
idvalue: ds.l 1
statusvalue: ds.l 1
freevalue: ds.l 1
loadedvalue: ds.l 1
versionvalue: ds.l 1
revisionvalue: ds.l 1
foundvalue: ds.l 1
buffer: ds.b 512
    cnop 0,4
board: ds.b gbi_SIZEOF
