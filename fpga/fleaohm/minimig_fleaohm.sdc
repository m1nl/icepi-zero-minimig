# Synplify treats DCSC as a black box. These abstract propagation arcs let
# generated clocks retain their selected PLL parent during synthesis.
# Diamond uses the actual device clock-network delays after mapping.
define_attribute {v:DCSC} syn_tpd1 {CLK0->DCSOUT=0}
define_attribute {v:DCSC} syn_tpd2 {CLK1->DCSOUT=0}

create_clock -name {clk} -period 40 [get_ports {clk}]
create_clock -name {clk_sys} -period 8.75 [get_nets {virtual_top.amiga_clk.clk_114}]
create_clock -name {clk_28m} -period 35 [get_nets {virtual_top.amiga_clk.clk_28}]
create_clock -name {clk_142m} -period 7 [get_nets {virtual_top.amiga_clk.clk_142}]
create_clock -name {clk_spi} -period 35 [get_nets {virtual_top.mycfide.sck}]

create_clock -name {clk_rtg_5x} -period 3.03 [get_nets {auxclks[0]}]
create_clock -name {clk_rtg} -period 15.15 [get_nets {auxclks[1]}]
create_clock -name {clk_usb} -period 16.67 [get_nets {auxclks[2]}]

# DCSC outputs are synchronous to the selected parent, not independent clocks.
create_generated_clock -name pixel_native -master_clock clk_28m -source [get_nets {virtual_top.amiga_clk.clk_28}] -divide_by 1 [get_nets {clk_pixel}]
create_generated_clock -name pixel_rtg -master_clock clk_rtg -source [get_nets {auxclks[1]}] -divide_by 1 -add [get_nets {clk_pixel}]
create_generated_clock -name tmds_native -master_clock clk_142m -source [get_nets {virtual_top.amiga_clk.clk_142}] -divide_by 1 [get_nets {clk_tmds}]
create_generated_clock -name tmds_rtg -master_clock clk_rtg_5x -source [get_nets {auxclks[0]}] -divide_by 1 -add [get_nets {clk_tmds}]

set_clock_groups -logically_exclusive -group [get_clocks {pixel_native tmds_native}] -group [get_clocks {pixel_rtg tmds_rtg}]

set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {clk_usb}] -group [get_clocks {clk_spi}] -group [get_clocks {clk_sys clk_28m clk_142m pixel_native tmds_native}] -group [get_clocks {clk_rtg clk_rtg_5x pixel_rtg tmds_rtg}]

set_multicycle_path -from [get_clocks {clk_28m}] -to [get_clocks {clk_sys}] 4
set_multicycle_path -from [get_clocks {clk_sys}] -to [get_clocks {clk_28m}] 2

set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\.pf68K_Kernel_inst\..*}] 4

set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\..*}] -to [get_cells -regexp {virtual_top\.sdram\..*}] 4
set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\..*}] -to [get_cells -regexp {virtual_top\.sdram\.cache\..*}] 3

set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.state*}] 3

set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.memaddr*}] 3
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.memaddr*}] -to [get_cells -regexp {virtual_top\.tg68k\.pf68K_Kernel_inst\..*}] 4

set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.addr[*]}] -to [get_cells -regexp {virtual_top\.sdram\..*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.addr[*]}] -to [get_cells -regexp {virtual_top\.sdram\.cache\..*}] 3

set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.data_write*}] -to [get_cells -regexp {virtual_top\.sdram\..*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.data_write*}] -to [get_cells -regexp {virtual_top\.sdram\.cache\..*}] 3

set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] 4
set_multicycle_path -to [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] 4

set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.ALU.*}] 4
set_multicycle_path -to [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.ALU.*}] 4

set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] -to [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] -to [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.ALU.*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] -to [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] -to [get_cells {virtual_top.tg68k.data_write*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] -to [get_cells -regexp {virtual_top\.sdram\..*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.pf68K_Kernel_inst.regfile*}] -to [get_cells -regexp {virtual_top\.sdram\.cache\..*}] 3

set_multicycle_path -from [get_cells {virtual_top.tg68k.addr[*]}] 3
set_multicycle_path -from [get_cells {virtual_top.tg68k.addr[*]}] -to [get_cells -regexp {virtual_top\.sdram\..*}] 4
set_multicycle_path -from [get_cells {virtual_top.tg68k.addr[*]}] -to [get_cells -regexp {virtual_top\.sdram\.cache\..*}] 3

set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\..*}] -to [get_cells {virtual_top.gen_rtg.rtg.*}] 3
set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\..*}] -to [get_cells {virtual_top.tg68k.u_akiko.*}] 3
set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\..*}] -to [get_cells {virtual_top.mycfide.amiga_buffer*}] 3

set_false_path -to [get_ports {led[*]}]

set_false_path -from [get_cells {virtual_top.mycfide.usbblock\.u_usb_hid_host_0.typ[*]}]
set_false_path -from [get_cells {virtual_top.mycfide.usbblock\.u_usb_hid_host_1.typ[*]}]
set_false_path -from [get_cells {virtual_top.mycfide.joystick_d*}]

set_false_path -from [get_cells {virtual_top.minimig.overclock*}]
set_false_path -from [get_cells {virtual_top.minimig.ide_config*}]
set_false_path -from [get_cells {virtual_top.minimig.chipset_config*}]
set_false_path -from [get_cells {virtual_top.minimig.memory_config*}]
set_false_path -from [get_cells {virtual_top.minimig.cpu_config*}]

set_false_path -from [get_cells {virtual_top.minimig.USERIO1.osd1.xoffset*}]
set_false_path -from [get_cells {virtual_top.minimig.USERIO1.osd1.yoffset*}]
set_false_path -from [get_cells {virtual_top.minimig.USERIO1.osd1.lr_filter*}]
set_false_path -from [get_cells {virtual_top.minimig.USERIO1.osd1.hr_filter*}]
set_false_path -from [get_cells {virtual_top.minimig.USERIO1.osd1.dither*}]

set_false_path -from [get_cells {virtual_top.minimig.AGNUS1.bc1.beamcon0*}]

# Native DVI signals are launched in the 28.6 MHz domain.
set_max_delay 34.96 -from [get_cells {virtual_top.DVI_*}] -to [get_cells {genvideo.hdmi_inst.*}]

set_false_path -to [get_cells {genvideo.audio_sync.*sync*}]
set_false_path -to [get_cells {genvideo.clock_control.reset_sync*}]
set_false_path -to [get_cells {genvideo.hdmi_inst.true_hdmi_output.packet_picker_inst.audio_sample_word_buffer*}]
set_false_path -to [get_cells {genvideo.hdmi_inst.serializer.reset_x5_sync*}]

set_false_path -to [get_cells {virtual_top.gen_rtg.rtg_resetn_sync*}]
set_false_path -to [get_cells {virtual_top.gen_rtg.rtg_irq_28_sync*}]
set_false_path -to [get_cells {virtual_top.gen_rtg.rtg.*sync*}]
set_false_path -to [get_cells {virtual_top.gen_rtg.rtg.*fifo.*sync*}]
set_false_path -to [get_cells {virtual_top.gen_rtg.rtg.config_meta*}]
set_false_path -to [get_cells {virtual_top.gen_rtg.rtg.ready_vid*}]
set_false_path -to [get_cells {virtual_top.gen_rtg.osd_rtg.enable_sync*}]

set_false_path -from [get_cells {virtual_top.gen_rtg.rtg.*fifo.rd_gray[*]}] -to [get_cells {virtual_top.gen_rtg.rtg.*fifo.rd_gray_w1[*]}]
set_false_path -from [get_cells {virtual_top.gen_rtg.rtg.*fifo.wr_gray[*]}] -to [get_cells {virtual_top.gen_rtg.rtg.*fifo.wr_gray_r1[*]}]

set_false_path -from [get_cells {virtual_top.minimig.AGNUS1.bc1.interlace_out*}]
set_false_path -from [get_cells {virtual_top.minimig.AGNUS1.bc1.displaypal_out*}]
set_false_path -from [get_cells {virtual_top.minimig.AGNUS1.bc1.long_frame_r*}]

# Direct word capture has at least two destination-clock cycles.
set_multicycle_path -from [get_cells {genvideo.hdmi_inst.tmds_gen*.tmds_channel.*}] -to [get_cells {genvideo.hdmi_inst.serializer.g_ser*.shift*}] 2

# Only the first pixel-marker synchronizer stage is exempt.
set_false_path -to [get_cells {genvideo.hdmi_inst.serializer.pixel_toggle_sync[0]}]

# Clock going to SDRAM (180° shifted)
create_generated_clock -name sdram_clk -source [get_nets {virtual_top.amiga_clk.clk_114}] -phase 180 [get_ports sdram_clk]

# Data/address/command setup requirement
set_output_delay -clock sdram_clk -max 1.5 [get_ports {sdram_*}]

# Hold requirement
set_output_delay -clock sdram_clk -min -0.8 [get_ports {sdram_*}]
