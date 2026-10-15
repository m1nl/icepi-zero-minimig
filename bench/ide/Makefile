IVERILOG ?= iverilog
VVP ?= vvp
ROOT := ../..
BUILD_DIR ?= /tmp/minimig-ide-tests

.PHONY: test
test: $(BUILD_DIR)/ide_packet_tb
	$(VVP) $(BUILD_DIR)/ide_packet_tb

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/ide_packet_tb: ide_packet_tb.v $(ROOT)/rtl/minimig/ide.v $(ROOT)/rtl/minimig/ide_fifo.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -s ide_packet_tb -o $@ $^
