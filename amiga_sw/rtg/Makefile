VBCC ?= $(HOME)/vbcc
AS = $(VBCC)/bin/vasmm68k_mot
XDFTOOL ?= xdftool
NDK_DIR ?= $(CURDIR)/.deps/NDK_3.9
INC_ASM ?= $(NDK_DIR)/Include/include_i
P96_PRIVATE ?= $(CURDIR)/.deps/Picasso96Develop/PrivateInclude
P96_PUBLIC ?= $(CURDIR)/.deps/Picasso96Develop/Include
VASM_FLAGS := -quiet -nowarn=1012 -m68020 -Fhunkexe -kick1hunks -nosym -no-opt

TARGET := minimig.card
SOURCE := minimig.card.asm
LISTFILE := minimig.card.lst
ADF := minimig-rtg.adf
DIAGNOSTIC := rtgcheck
LVO_FILES := $(addprefix .deps/lvo/,$(addsuffix _lib.i,exec intuition expansion graphics dos))
INCLUDES := $(P96_PRIVATE)/boardinfo.i $(P96_PRIVATE)/settings.i \
            $(P96_PUBLIC)/libraries/Picasso96.i \
            $(wildcard $(INC_ASM)/*/*.i) $(LVO_FILES)

.PHONY: all adf deps clean
all: $(TARGET) $(DIAGNOSTIC) $(ADF)
adf: $(ADF)

$(TARGET): $(SOURCE) Makefile $(INCLUDES)
	$(AS) $(SOURCE) -o $@ -L $(LISTFILE) $(VASM_FLAGS) \
		-I "$(INC_ASM)/" -I "$(P96_PRIVATE)/" -I "$(P96_PUBLIC)/" -I .deps/

$(DIAGNOSTIC): rtgcheck.asm Makefile $(INCLUDES)
	$(AS) $< -o $@ $(VASM_FLAGS) \
		-I "$(INC_ASM)/" -I "$(P96_PRIVATE)/" -I "$(P96_PUBLIC)/" -I .deps/

$(ADF): $(TARGET) $(DIAGNOSTIC) README Makefile
	$(XDFTOOL) -f "$@.tmp.adf" create + format MinimigRTG ofs \
		+ makedir Libs + makedir Libs/Picasso96 \
		+ write "$(TARGET)" Libs/Picasso96/$(TARGET) + write "$(DIAGNOSTIC)" + write README
	mv "$@.tmp.adf" "$@"

.deps/lvo/%_lib.i: $(NDK_DIR)/Include/fd/%_lib.fd fd_to_lvo.py
	python3 fd_to_lvo.py $< $@

clean:
	$(RM) $(TARGET) $(DIAGNOSTIC) $(LISTFILE) $(ADF) $(ADF).tmp.adf

# Grouped targets prevent duplicate downloads during parallel builds (GNU make 4.3+).
DEFAULT_NDK := $(CURDIR)/.deps/NDK_3.9
NDK_FILES := $(DEFAULT_NDK)/Include/include_i/hardware/custom.i \
             $(addprefix $(DEFAULT_NDK)/Include/fd/,$(addsuffix _lib.fd,exec intuition expansion graphics dos))
PUBLIC_FILES := $(CURDIR)/.deps/Picasso96Develop/Include/libraries/Picasso96.i
PRIVATE_FILES := $(addprefix $(CURDIR)/.deps/Picasso96Develop/PrivateInclude/,boardinfo.i settings.i)

deps: $(NDK_FILES) $(PUBLIC_FILES) $(PRIVATE_FILES)

$(NDK_FILES) &:
	bash download_deps.sh ndk

$(PUBLIC_FILES) &:
	bash download_deps.sh public

$(PRIVATE_FILES) &:
	bash download_deps.sh private
