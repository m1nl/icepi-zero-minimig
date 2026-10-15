from pathlib import Path
s=Path('amiga_sw/rtg/minimig.card.asm').read_text()
rom='''    machine 68020
    include libraries/Picasso96.i
    include boardinfo.i
    include settings.i
CardData_ModeValid = gbi_CardData+26
CardData_VRepeat = gbi_CardData+28
RTG_DISPLAY_SWITCH = $10
RTG_REPEAT = $14
RTG_STRIDE = $16
RTG_RGB_FORMATS EQU (RGBFF_CLUT|RGBFF_R5G6B5|RGBFF_R5G5B5)
    org 0
    dc.l $2000,$100
    dcb.b $100-*,0
start:
    lea $1400,a0
    lea $1800,a1
    move.l #$b80100,gbi_RegisterBase(a0)
'''
for yi,h in enumerate((768,384,256)):
 for xi,w in enumerate((1024,512,320)):
  enc=xi+4*yi; idx=xi+3*yi
  rom+=f'''    move.w #{w},gmi_Width(a1)
    move.w #{h},gmi_Height(a1)
    bsr ModeRepeat
    cmpi.l #{enc},d0
    bne fail
    cmpi.l #{idx},d1
    bne fail
    moveq #0,d0
    bsr SetGC
    move.w $b80114,d0
    cmpi.w #{enc},d0
    bne fail
    cmpi.w #1,CardData_ModeValid(a0)
    bne fail
'''
for w,h in ((960,384),(512,350),(0,768),(1024,769)):
 rom+=f'''    move.w #{w},gmi_Width(a1)
    move.w #{h},gmi_Height(a1)
    bsr ModeRepeat
    cmpi.l #-1,d0
    bne fail
    moveq #0,d0
    bsr SetGC
    tst.w CardData_ModeValid(a0)
    bne fail
    move.w $b80110,d0
    tst.w d0
    bne fail
'''
for width in (1024,512,320,960,480,300,0,1,16,17,4096):
 for fmt,bpp in ((1,1),(10,2),(11,2)):
  rom+=f'''    move.l #{width},d0
    move.l #{fmt},d7
    bsr CalculateBytesPerRow
    cmpi.w #{(width*bpp+15)&~15},d0
    bne fail
'''
for fmt in (0,2,4,6,12,15,16,-1):
 rom+=f'''    move.l #17,d0
    move.l #{fmt},d7
    bsr CalculateBytesPerRow
    tst.l d0
    bne fail
'''
for fmt in (1,10,11,0,2,4,6,12,15,16,-1):
 expected=3074 if fmt in (1,10,11) else 0
 rom+=f'''    move.l #{fmt},d7
    bsr GetCompatibleFormats
    cmpi.l #{expected},d0
    bne fail
'''
rom+='''    move.w #$600d,$1000
loop:
    bra loop
fail:
    move.w #$dead,$1000
    bra fail
'''
rom+=s[s.index('SetGC:'):s.index(';------------------------------------------------------------------------------\nSetPanning:')]
rom+=s[s.index('CalculateBytesPerRow:'):s.index(';------------------------------------------------------------------------------\nCalculateMemory:')]
rom+=s[s.index('GetCompatibleFormats:'):s.index('SetSplitPosition:')]
Path('/tmp/rtg_driver_repeat.asm').write_text(rom)
tb=Path('bench/rtg_hdmi/rtg_cpu_mmio_tb.v').read_text()
tb=tb.replace('.rtg_ena(', '.rtg_active(')
a=tb.index('  if({rtg.rtg_base'); b=tb.index('\n end',a)
tb=tb[:a]+'''  $display("PASS: actual 68020 driver scale selection, mode rejection, MMIO, aligned bitmap rows and supported format masks");$finish;'''+tb[b:]
Path('/tmp/rtg_driver_repeat_tb.v').write_text(tb)
