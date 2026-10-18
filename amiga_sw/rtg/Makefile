VBCC ?= $(HOME)/vbcc
AS = $(VBCC)/bin/vasmm68k_mot
XDFTOOL ?= xdftool
NDK_DIR ?= $(CURDIR)/.deps/NDK_3.9
INC_ASM ?= $(NDK_DIR)/Include/include_i
P96_PRIVATE ?= $(CURDIR)/.deps/Picasso96Develop/PrivateInclude
P96_PUBLIC ?= $(CURDIR)/.deps/Picasso96Develop/Include
VASM_FLAGS := -quiet -nowarn=1012 -m68020 -Fhunkexe -kick1hunks -nosym -no-opt
DEBUG ?= 0
ifeq ($(DEBUG),1)
DEBUG_FLAGS := -DRTG_DEBUG=1
else ifneq ($(DEBUG),0)
$(error DEBUG must be 0 or 1)
endif
DEBUG_CONFIG := .deps/driver-debug.cfg
TEST_PROFILE ?= all

TARGET := minimig.card
TARGET_720P := minimig-720p.card
SOURCE := minimig.card.asm
LISTFILE := minimig.card.lst
LISTFILE_720P := minimig-720p.card.lst
ADF := minimig-rtg.adf
ADF_720P := minimig-rtg-720p.adf
DIAGNOSTIC := rtgcheck
LVO_FILES := $(addprefix .deps/lvo/,$(addsuffix _lib.i,exec intuition expansion graphics dos))
INCLUDES := $(P96_PRIVATE)/boardinfo.i $(P96_PRIVATE)/settings.i \
            $(P96_PUBLIC)/libraries/Picasso96.i \
            $(wildcard $(INC_ASM)/*/*.i) $(LVO_FILES)

.PHONY: all adf deps clean test FORCE
all: $(TARGET) $(TARGET_720P) $(DIAGNOSTIC) $(ADF) $(ADF_720P)
adf: $(ADF) $(ADF_720P)

test: $(INCLUDES)
	python3 tests/run.py --profile "$(TEST_PROFILE)" --vasm "$(AS)" \
		--inc-asm "$(INC_ASM)" --p96-private "$(P96_PRIVATE)" \
		--p96-public "$(P96_PUBLIC)" \
		$(if $(CPU_NETLIST),--cpu-netlist "$(CPU_NETLIST)",)

$(TARGET): $(SOURCE) Makefile $(INCLUDES) $(DEBUG_CONFIG)
	$(AS) $(SOURCE) -o $@ -L $(LISTFILE) $(VASM_FLAGS) $(DEBUG_FLAGS) \
		-I "$(INC_ASM)/" -I "$(P96_PRIVATE)/" -I "$(P96_PUBLIC)/" -I .deps/

$(TARGET_720P): $(SOURCE) Makefile $(INCLUDES) $(DEBUG_CONFIG)
	$(AS) $(SOURCE) -o $@ -L $(LISTFILE_720P) $(VASM_FLAGS) $(DEBUG_FLAGS) -DRTG_720P=1 \
		-I "$(INC_ASM)/" -I "$(P96_PRIVATE)/" -I "$(P96_PUBLIC)/" -I .deps/

# Rebuild when DEBUG changes, retaining the timestamp for unchanged options.
$(DEBUG_CONFIG): FORCE
	@mkdir -p .deps
	@if ! test -f "$@" || ! test "$$(cat "$@")" = "$(DEBUG)"; then \
		printf '%s\n' "$(DEBUG)" > "$@"; \
	fi

FORCE:

$(DIAGNOSTIC): rtgcheck.asm Makefile $(INCLUDES)
	$(AS) $< -o $@ $(VASM_FLAGS) \
		-I "$(INC_ASM)/" -I "$(P96_PRIVATE)/" -I "$(P96_PUBLIC)/" -I .deps/

$(ADF): $(TARGET) $(DIAGNOSTIC) README Makefile
	$(XDFTOOL) -f "$@.tmp.adf" create + format MinimigRTG ofs \
		+ makedir Libs + makedir Libs/Picasso96 \
		+ write "$(TARGET)" Libs/Picasso96/$(TARGET) + write "$(DIAGNOSTIC)" + write README
	mv "$@.tmp.adf" "$@"

$(ADF_720P): $(TARGET_720P) $(DIAGNOSTIC) README Makefile
	$(XDFTOOL) -f "$@.tmp.adf" create + format MinimigRTG720p ofs \
		+ makedir Libs + makedir Libs/Picasso96 \
		+ write "$(TARGET_720P)" Libs/Picasso96/$(TARGET) + write "$(DIAGNOSTIC)" + write README
	mv "$@.tmp.adf" "$@"

.deps/lvo/%_lib.i: $(NDK_DIR)/Include/fd/%_lib.fd fd_to_lvo.py
	python3 fd_to_lvo.py $< $@

clean:
	$(RM) $(TARGET) $(TARGET_720P) $(DIAGNOSTIC) $(LISTFILE) $(LISTFILE_720P) \
		$(ADF) $(ADF_720P) $(ADF).tmp.adf $(ADF_720P).tmp.adf

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
