BASE	=
832DIR = ../../EightThirtyTwo
CC      = $(832DIR)/vbcc/bin/vbcc832
GCC		= gcc
LD      = $(832DIR)/832a/832l
AS      = $(832DIR)/832a/832a
CP      = objcopy
DUMP    = objdump

BUILD_DIR = 832obj
LIB_DIR=$(832DIR)/lib832
INCLUDE_DIR = $(832DIR)/include
STARTUP_DIR = $(832DIR)/Lib

ROMGEN = ../../EightThirtyTwo/romgen/romgen

# we use mincrt0.s from here
STARTUP_DIR = .

# we fetch ROM prologue / epilogue from here
RTL_DIR = ./

PROJECT=OSDBoot_832

### flags ###

CFLAGS  = -+ -c99 -Dprg_start=0x2000 -DOSDNAME=\"832OSDU0BIN\" -O=1311 -size -unsigned-char -DNULL=0 -I. -I$(INCLUDE_DIR)/ -I$(COMMON_DIR)/ -I../OSD/
ASFLAGS = -eb
LDFLAGS  = -eb -s_STACKSIZE=0x240
ROMGENFLAGS =

### variables ###

# headers
HEADERS=spr_defs.h or32_defs.h hardware.h string.h swap.h errors.h mmc.h fat.h

# common sources
COMMON_SOURCES=$(BUILD_DIR)/boot.o $(BUILD_DIR)/spi.o $(BUILD_DIR)/swap.o \
	$(BUILD_DIR)/minfat.o $(BUILD_DIR)/uart.o $(BUILD_DIR)/checksum.o $(BUILD_DIR)/hexdump.o

# all sources
ALL_SOURCES = $(LIB_DIR)/crt0.a $(ASM_SOURCES) $(COMMON_SOURCES) $(LIB_DIR)/lib832.a

### build rules ###

all: $(PROJECT).bin $(PROJECT)_ROM.vhd

$(PROJECT).bin: bootdiag.h $(ALL_SOURCES)
	$(LD) $(LDFLAGS) -M $(PROJECT).map -o $@ $(ALL_SOURCES)

# clean
clean:
	@echo clean
	@-rm -rf $(BUILD_DIR)/*.o
	@-rm *.asm

$(ROMGEN): ../romgen/romgen.c
	make -C ../romgen/

%_ROM.vhd: %.bin $(ROMGEN)
	sed 's/soc_firmware/$*_ROM/' >$*_ROM.vhd <$(RTL_DIR)/rom_prologue.vhd
	$(ROMGEN) $*.bin >>$*_ROM.vhd
	cat >>$*_ROM.vhd $(RTL_DIR)/rom_epilogue.vhd
	sed 's/soc_firmware/$*_ROM/' >$*_ROM_word.vhd <$(RTL_DIR)/rom_prologue_word.vhd
	$(ROMGEN) -w $*.bin >>$*_ROM_word.vhd
	cat >>$*_ROM_word.vhd $(RTL_DIR)/rom_epilogue_word.vhd

bootdiag.h: bootdiag.s
	vasmm68k_mot -Fbin bootdiag.s -o bootdiag.bin
	xxd -i bootdiag.bin > bootdiag.h

%.asm: %.c
	$(CC) $(CFLAGS) -o=$@ $<

$(BUILD_DIR)/%.o: %.asm $(BUILD_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/%.o: $(STARTUP_DIR)/%.S $(BUILD_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR):
	mkdir $(BUILD_DIR)

