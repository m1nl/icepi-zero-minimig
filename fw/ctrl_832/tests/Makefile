CC ?= cc
ROOT := ../../..
FW := ..
BUILD_DIR ?= /tmp/minimig-fw-tests
SANITIZE ?= -fsanitize=address,undefined
CFLAGS := -std=c99 -g -Wall -Wextra -Wno-int-to-pointer-cast

.PHONY: test
test: $(BUILD_DIR)/atapi_test $(BUILD_DIR)/fat_test $(BUILD_DIR)/hdd_bounds_test $(BUILD_DIR)/hdd_bounds_read_unchecked_test $(BUILD_DIR)/mmc_error_test
	ASAN_OPTIONS=detect_leaks=0 $(BUILD_DIR)/atapi_test
	ASAN_OPTIONS=detect_leaks=0 $(BUILD_DIR)/fat_test
	ASAN_OPTIONS=detect_leaks=0 $(BUILD_DIR)/hdd_bounds_test
	ASAN_OPTIONS=detect_leaks=0 $(BUILD_DIR)/hdd_bounds_read_unchecked_test
	ASAN_OPTIONS=detect_leaks=0 $(BUILD_DIR)/mmc_error_test

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/atapi_test: atapi_test.c $(FW)/cdrom.c $(FW)/cdrom_image.c $(FW)/cdrom.h $(FW)/cdrom_image.h $(FW)/hdd.h $(FW)/fat.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Werror $(SANITIZE) -I$(FW) atapi_test.c $(FW)/cdrom.c $(FW)/cdrom_image.c -o $@

# Suppress warnings in legacy FAT/browser code outside this feature's scope.
$(BUILD_DIR)/fat_test: fat_test.c $(FW)/fat.c $(FW)/fat.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SANITIZE) -Wno-format -Wno-unused-variable -Wno-unused-but-set-variable -Wno-sign-compare -Wno-char-subscripts -Wno-misleading-indentation -Wno-stringop-overread -ffunction-sections -fdata-sections -I$(FW) -I$(ROOT)/EightThirtyTwo/lib832 fat_test.c $(FW)/fat.c -Wl,--gc-sections -o $@

$(BUILD_DIR)/hdd_bounds_test: hdd_bounds_test.c $(FW)/hdd.c $(wildcard $(FW)/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SANITIZE) -Wno-format -Wno-unused-parameter -Wno-unused-variable -ffunction-sections -fdata-sections -I$(FW) -I$(ROOT)/EightThirtyTwo/lib832 hdd_bounds_test.c -Wl,--gc-sections -o $@

# Exercise the optional read-only bypass without changing production flags.
$(BUILD_DIR)/hdd_bounds_read_unchecked_test: hdd_bounds_test.c $(FW)/hdd.c $(wildcard $(FW)/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SANITIZE) -DHDD_DISABLE_READ_RANGE_CHECK -Wno-format -Wno-unused-parameter -Wno-unused-variable -ffunction-sections -fdata-sections -I$(FW) -I$(ROOT)/EightThirtyTwo/lib832 hdd_bounds_test.c -Wl,--gc-sections -o $@

$(BUILD_DIR)/mmc_error_test: mmc_error_test.c $(FW)/mmc.c $(wildcard $(FW)/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SANITIZE) -Wno-format -Wno-unused-variable -Wno-unused-but-set-variable -ffunction-sections -fdata-sections -I$(FW) -I$(ROOT)/EightThirtyTwo/lib832 mmc_error_test.c -Wl,--gc-sections -o $@
