# Firmware regression checks

Run `make -C fw/ctrl_832/tests test` from the repository root. Requires a native C
compiler. Build products go to `/tmp/minimig-fw-tests`.
The native tests use AddressSanitizer and UndefinedBehaviorSanitizer; leak
checking is disabled because it fails in ptraced execution environments.
Override `SANITIZE=` only when the compiler lacks sanitizer support.

- `atapi_test.c` exercises the production image and packet modules using
  in-memory files and scripted SPI: ISO/random/end reads, single- and multi-file
  mixed CUE tracks, raw Mode 1/XA Form 1 payloads, Form 2 rejection, invalid images,
  split/odd responses, sense, tray loading, locking, live swaps, and cancellation.
- `fat_test.c` exercises production FAT16/FAT32 seek/read code against a small
  fragmented disk, including buffered and direct cluster crossings, exact EOF,
  recoverable failures, exact filenames, and relative directory lookup. FAT
  numeric directory fields are modeled with the controller's byte swapping.
- `hdd_bounds_test.c` includes production HDD code with mocked hardware/storage.
  It covers capacity calculation at open/remount, synthetic-RDB capacity, complete
  transfer bounds, partition offsets, failure invalidation, and the seek-index
  guard. It also injects seek/read/write failures and verifies error completion,
  including successful last-sector writes without an unnecessary EOF seek.
  It checks multiple-mode sizes, disabling, invalid settings, partial final
  blocks, IDENTIFY reporting and reopening with multiple mode disabled.
  It reproduces the 201 MiB PFS3 image boundary: block 411647 remains readable
  and writable when CHS has a partial final cylinder, IDENTIFY reports all
  411648 sectors, and transfers beyond EOF are rejected. Transfer checks perform
  no SD-capacity lookup. The suite runs this test both with normal read bounds
  and with the optional read-range-check bypass enabled for the test binary.
- `mmc_error_test.c` exercises production SD I/O with scripted SPI responses:
  rejected commands/data, missing data tokens, stop-transmission failures,
  busy timeouts and successful final-sector I/O. It verifies command end bits and
  CRC7, CS-high startup/completion clocks, ready-before-command behavior, immediate
  and delayed legacy ACMD41 success, SDHC initialization, and failed CMD9/CMD16/CMD58
  propagation without stale capacity. It also checks immediate decoding
  of all read-error tokens, physical versus command addresses, elapsed token waits,
  unexpected bytes, and the failing sector within a multi-block read. Quiet APIs return failures
  without invoking `FatalError`; legacy APIs retain fatal error reporting.

- `boot_spi_test.c` exercises the production bootstrap reader from
  `fw/ctrl_boot_832/spi.c`: SDHC, v2/legacy SDSC and MMC initialization, immediate
  and delayed ACMD41 completion, CMD0/CMD8 framing, CMD16/CMD58 failures, OCR/echo
  validation, byte/block addressing, unaligned destinations, both CRC bytes,
  completion clocks, card-ready waits, read-error tokens and timeout cleanup.
  The bootstrap exports only `spi_init()` and `sd_read_sector()`; it has no write
  or multi-block path. Its ROM is embedded in the FPGA: regenerate the boot ROM
  with `make -C fw/ctrl_boot_832` before rebuilding the selected board's HDL.

The SD SPI RTL simulation runs separately with `make -C bench/sd test`; see
[the SD testbench README](../../../bench/sd/README.md). It checks the production
engine against the current firmware divider settings.

The IDE/FIFO RTL simulation runs separately with `make -C bench/ide test`; see
[the IDE testbench README](../../../bench/ide/README.md).

The existing `configuration_titles.c` test has separate build instructions in
[CONFIGURATION_TITLES.md](../docs/CONFIGURATION_TITLES.md).

These tests do not establish Amiga driver compatibility or board timing.

## Hardware acceptance with IDEfix97 / CacheCDFS

1. Rebuild the IcePi HDL, copy `fw/ctrl_832/832OSDU0.bin` to the SD card, and
   configure primary slave as CD-ROM in **Storage / IDE**. Apply/reset once.
2. Verify discovery with an empty drive, then open its media menu and insert
   ISO. Allow the guest driver's normal media-change polling. Mount/read a known
   file and compare its checksum against the source ISO.
3. Replace with another ISO, then a single-BIN and a multi-BIN CUE; check data
   and mixed-mode TOCs. No Amiga reset should occur for these media changes.
4. Eject/reinsert, try a missing backing file and a malformed CUE, and verify
   the previous image survives failed insertion. Check guest removal locking.
5. Read fragmented images and their final data blocks; exercise guest reset
   during a long read and verify subsequent reads and OSD use remain possible.
6. Verify the neighboring ATA disk still boots and reads/writes normally.

No CD audio playback, raw READ CD commands, WAVE/MP3 backing files, or CD32
emulation is supplied. Mode 2 reads require XA Form 1 sectors. Multiple sessions
and POSTGAP/extra INDEX points are rejected rather than guessed.

## ATA read bounds option

`HDD_DISABLE_READ_RANGE_CHECK` is intentionally undefined. Defining it in a custom
firmware build skips command-level bounds validation for ATA reads only. Write
validation and the hardfile seek-index guard stay enabled. Cached capacity is
calculated when opening the device; it is not recalculated per read or write.

## SD read diagnostics

CMD17/CMD18 failures print details to the serial log: physical sector (decimal),
command argument (hexadecimal), card type, received token, wait time in
milliseconds, poll count, and first/last unexpected bytes. Card type 3 uses sector
addresses (SDHC/SDXC); types 1/2 use byte addresses (MMC/SDSC). For CMD18, the
physical sector identifies the failed block while the argument remains the
stream's starting address. Read-error tokens decode general error, card-controller
error, ECC failure and out-of-range flags; CMD12 cleanup failures are also logged.

The OSD distinguishes missing tokens from card-reported data errors. Use the
left/right arrows to browse three detail pages and any other pending error
categories. They show the physical sector and command argument in hexadecimal,
card type/addressing mode, token, elapsed milliseconds, poll count, first/last
unexpected bytes, unexpected-byte count, decoded error flags, and CMD12 response
for multi-block failures. All rows fit the 32-character OSD width. No serial
output is needed. The first pending SD snapshot stays visible until OK/Reboot;
drawing or browsing pages does not clear it or lose fatal severity.

An all-`0xFF` or all-`0x00` wait retains the existing 1,000,001-byte polling limit.
Quiet token failures raise a nonfatal OSD error and return failure; legacy calls
remain fatal. The diagnostic polling limit is independent of SPI initialization speed;
no automatic retries are added.
The SD tests render the production error pages through a mocked OSD and check
all fields, page clearing, snapshot lifetime and fatal/nonfatal handling.

## SD transaction handling

Initialization supplies 80 clocks with CS/MOSI high and uses divider `0x48`:
about 389 kHz with CS low and 394 kHz with CS high at the supported boards' system
clock. Normal selected transfers remain about 11.43 MHz. Transaction exits clock
an extra `0xFF` byte with CS high after consuming the response/data CRC. Commands
wait up to one second for ready before transmission; CMD0 can reset a busy card,
and CMD12 interrupts a read stream through its dedicated path with valid CRC7
and end bit. Capacity is invalidated before CMD9 and initialization fails if the
CSD cannot be read. Malformed CSD fields cannot trigger an invalid block-size shift.

No production HDL or bootstrap change is needed. Simulation does not establish
SD pin setup/hold margins; the existing board constraints lack SD I/O delays.
Electrical timing validation still needs card/board timing data and hardware
measurement rather than assumed delay values.

- `keyboard_queue_test.c` checks FIFO ordering and send-once delivery, guest
  acknowledgements, the 20 ms timeout boundary, timer/queue wrap, bounded
  overflow, mouse bypass and interrupt protection. The queue holds 127 keys,
  including its in-flight head; overflow rejects the newest key and increments
  `keyboard_queue_overflows`.

The head event is sent unchanged through the existing FPGA interface exactly
once. ACK or 20 ms without ACK discards it and permits the next queued key.
The timeout uses `GetTimer(20)` and `CheckTimer()`. The wait starts at
transmission and is not extended by new arrivals; each
subsequent transmission starts a fresh wait. Expiry is checked by the next
cooperative service call, with the existing hardware timer resolution. Mouse
and OSD-only (type-3) events bypass the queue; ordinary type-2 keys reach the
OSD with their single queued delivery. No new FPGA status bits are required.
The timeout deliberately permits replacement of an unread key after 20 ms.
