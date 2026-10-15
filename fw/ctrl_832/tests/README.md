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
  busy timeouts and successful final-sector I/O. Quiet APIs return failures
  without invoking `FatalError`; legacy APIs retain fatal error reporting.

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
