    machine 68020
    ifnd AKIKO_PAD
AKIKO_PAD equ 0
    endif
    org 0
    dc.l $2000,$100
    dcb.b $100-*,0
start:
    move.l #$101,d0
    movec d0,cacr
    lea $1400,a0
    lea $1600,a1
    lea $b80038,a2
    move.l #$100,d1
    lea (a1,d1.w),a3
    lea (a3,d1.w),a4
    lea (a4,d1.w*2),a5
    lea (a5,d1.w*2),a6
    moveq #7,d7
    ; Exercise every instruction-pair position within a 16-byte cache line.
    rept AKIKO_PAD
    nop
    endr
c2pal:
    ; Doom-style C2P traffic: eight chunky longwords into Akiko, then eight
    ; planar longwords out to separate planes. Each MMIO longword stays narrow.
    rept 8
    move.l (a0)+,(a2)
    endr
    move.l (a2),(a1)+
    move.l (a2),(a3)+
    move.l (a2),(a4)+
    move.l (a2),$100(a4)
    move.l (a2),(a5)+
    move.l (a2),$100(a5)
    move.l (a2),(a6)+
    move.l (a2),$100(a6)
    dbf d7,c2pal
    move.w #$600d,$1000
stop:
    bra stop
    org $1400
    rept 64
    dc.l $01234567
    endr
