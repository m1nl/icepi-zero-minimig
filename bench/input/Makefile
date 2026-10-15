IVERILOG ?= iverilog
VVP ?= vvp
BOARD ?= icepi-zero
BUILD_DIR ?= /tmp/minimig-input-tests
ROOT := ../..
SOURCES := input_events_tb.sv $(ROOT)/rtl/soc/minimig_virtual_top.v \
	$(ROOT)/rtl/minimig/userio.v $(ROOT)/rtl/minimig/amiga_keyboard.v \
	$(ROOT)/rtl/minimig/userio_osd.v $(ROOT)/rtl/minimig/userio_osd_spi.v \
	$(ROOT)/rtl/fifo/sync_fifo.v

.PHONY: test
test:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -i -I $(ROOT)/fpga/$(BOARD) -I $(ROOT)/rtl/soc \
		-I $(ROOT)/rtl/minimig -s input_events_tb -o $(BUILD_DIR)/input_events_tb $(SOURCES)
	$(VVP) $(BUILD_DIR)/input_events_tb
