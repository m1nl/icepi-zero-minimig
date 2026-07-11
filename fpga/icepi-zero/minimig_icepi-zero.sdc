create_clock -name {clk} -period 20 [get_ports {clk}]
create_clock -name {clk_sys} -period 8.75 [get_nets {virtual_top.amiga_clk.clk_114}]
create_clock -name {clk_pixel} -period 35 [get_nets {virtual_top.amiga_clk.clk_28}]
create_clock -name {clk_tmds} -period 7 [get_nets {virtual_top.amiga_clk.clk_142}]
create_clock -name {clk_usb} -period 16.67 [get_nets {auxclks[0]}]
create_clock -name {clk_spi} -period 35 [get_nets {virtual_top.mycfide.sck}]

set_clock_groups -asynchronous -group [get_clocks {clk_usb}] -group [get_clocks {clk_sys clk_pixel clk_tmds}] -group [get_clocks {clk_spi}]

set_multicycle_path -from [get_clocks {clk_pixel}] -to [get_clocks {clk_sys}] 4
set_multicycle_path -from [get_clocks {clk_sys}] -to [get_clocks {clk_pixel}] 2

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

set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\..*}] -to [get_cells {virtual_top.tg68k.u_akiko.*}] 3
set_multicycle_path -from [get_cells -regexp {virtual_top\.tg68k\..*}] -to [get_cells {virtual_top.mycfide.amiga_buffer*}] 3

set_false_path -to [get_ports {led[*]}]

set_false_path -from [get_cells {virtual_top.mycfide.usbblock\.u_usb_hid_host_0.typ[*]}]
set_false_path -from [get_cells {virtual_top.mycfide.usbblock\.u_usb_hid_host_1.typ[*]}]
set_false_path -from [get_cells {virtual_top.minimig.ide_config*}]
set_false_path -from [get_cells {virtual_top.minimig.chipset_config*}]
set_false_path -from [get_cells {virtual_top.minimig.cpu_config*}]
set_false_path -from [get_cells {virtual_top.minimig.AGNUS1.bc1.beamcon0*}]

# Clock going to SDRAM (180° shifted)
create_generated_clock -name sdram_clk -source [get_nets {virtual_top.amiga_clk.clk_114}] -phase 180 [get_ports sdram_clk]

# Data/address/command setup requirement
set_output_delay -clock sdram_clk -max 1.5 [get_ports {sdram_*}]

# Hold requirement
set_output_delay -clock sdram_clk -min -0.8 [get_ports {sdram_*}]
