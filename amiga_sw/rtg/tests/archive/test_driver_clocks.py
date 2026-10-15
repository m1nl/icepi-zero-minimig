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
clocks=(66000000,33000000,22000000,33000000,16500000,11000000,22027295,11013648,7342432)
for yi,h in enumerate((768,384,256)):
 for xi,w in enumerate((1024,512,320)):
  idx=xi+3*yi
  ht=(1344,672,448)[xi]; vt=(806,403,269)[yi]
  for fmt,bpp in ((1,1),(10,2),(11,2)):
   rom+=f'''    move.w #{w},gmi_Width(a1)
    move.w #{h},gmi_Height(a1)
    move.l #{fmt},d7
    move.l #25000000,d0
    bsr ResolvePixelClock
    cmpi.l #{idx},d0
    bne fail
    cmpi.l #{clocks[idx]},gmi_PixelClock(a1)
    bne fail
    cmpi.w #{ht},gmi_HorTotal(a1)
    bne fail
    cmpi.w #{vt},gmi_VerTotal(a1)
    bne fail
    cmpi.w #{ht-w},gmi_HorBlankSize(a1)
    bne fail
    cmpi.w #{vt-h},gmi_VerBlankSize(a1)
    bne fail
    bsr GetPixelClock
    cmpi.l #{clocks[idx]},d0
    bne fail
    cmpi.l #{bpp},d1
    bne fail
'''
rom+='''    move.w #$600d,$1000
loop:
    bra loop
fail:
    move.w #$dead,$1000
    bra fail
'''
rom+=s[s.index('ResolvePixelClock:'):s.index('SetInterrupt:')]
Path('/tmp/rtg_driver_repeat.asm').write_text(rom)
tb=Path('bench/rtg_hdmi/rtg_cpu_mmio_tb.v').read_text()
tb=tb.replace('.rtg_ena(', '.rtg_active(')
a=tb.index('  if({rtg.rtg_base'); b=tb.index('\n end',a)
tb=tb[:a]+'''  $display("PASS: actual 68020 ResolvePixelClock/GetPixelClock, all 9 geometries and 3 supported formats");$finish;'''+tb[b:]
Path('/tmp/rtg_driver_repeat_tb.v').write_text(tb)
