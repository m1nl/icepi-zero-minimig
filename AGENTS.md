# Repository Guidelines

## Project Structure & Module Organization

Only **IcePi Zero, IcePi Zero XL and FleaFPGA Ohm** are supported and verified working. Other boards are retained for historical reasons and are out of scope unless explicitly requested.

- `rtl/`: hardware sources. Shared integration lives in `rtl/soc/`; chipset, SDRAM, HDMI and RTG logic have separate directories.
- `fpga/icepi-zero/`, `fpga/fleaohm/`: board projects, Diamond build scripts, SDC timing constraints and LPF pin/placement constraints.
- `fw/`: controller and boot firmware; `fw/ctrl_832/` supplies OSD and storage handling.
- `amiga_sw/rtg/`: Picasso96 assembly driver, dependency downloader and driver simulations.
- `bench/`: RTL simulations, resource assessments and historical reproductions. Consult `bench/README.md` before choosing tests.
- `doc/`: documentation.

Initialize required submodules with `git submodule update --init --recursive`. Check for directory-specific `AGENTS.md` instructions before editing nested modules.

## Build, Test, and Development Commands

Run from the repository root:

- `./fpga/icepi-zero/build.sh`: build the standard IcePi Zero project using Lattice Diamond and `grc`; use `build_xl.sh` for XL.
- `./fpga/fleaohm/build.sh`: build the FleaOhm project.
- `make -C amiga_sw/rtg`: assemble the driver and generate its transfer ADF. Requires installed vasm; missing headers download into `.deps/`. Add `RTG_720P=1` for the alternate raster.
- `make -C amiga_sw/rtg test`: simulate driver callbacks on TG68K/RTG hardware using GHDL and Icarus Verilog.
- `python3 bench/rtg_hdmi/run.py`: run focused video regressions; longer cases use Verilator.
- `make -C fw/ctrl_832 832OSDU0.bin`: build controller firmware using the EightThirtyTwo tools in the submodule; copy the resulting binary to the SD-card root.
- `make -C fw/ctrl_832/tests test`: run native firmware regressions with sanitizers.
- `make -C bench/ide test`: simulate IDE/FIFO transport.

## Coding Style & Naming Conventions

Preserve indentation, tabs, line endings and HDL dialect. Separate functional changes from formatting. Use descriptive signals, named generate blocks and existing naming conventions. Document clock domains, reset polarity and timing assumptions. Use Verilator lint and `git diff --check`.

## Testing Guidelines

Name HDL benches `*_tb.v` or `*_tb.sv`. Add behavior-focused regression coverage for changed interfaces, boundary conditions and reset/restart behavior. Keep driver tests in `amiga_sw/rtg/tests/` and firmware tests beside their firmware. Historical benches may target obsolete RTL. Simulation success does not establish FPGA timing closure: inspect the selected board's build and timing reports.

## Controller Firmware and Storage

- `hdd.c` handles ATA disks and shared IDE transport; `cdrom.c` handles ATAPI commands, sense and live media changes; `cdrom_image.c` handles ISO/CUE layout and image reads. Shared transport declarations belong in `hdd.h`, with `IDE*` names (`IDEWriteTaskFile`, `IDEWriteStatus`, `IDETransportState`, etc.). `HandleIDE` dispatches both ATA and ATAPI. Keep CD-specific APIs in `cdrom.h`.
- One optional CD-ROM occupies one of the four IDE slots. Configure **CD-ROM** in **Storage / IDE** and apply/reset once; subsequent **Insert ISO / CUE**, replace and eject operations must not reboot the Amiga or reopen neighboring HDDs. Types `HDF_CDROM=7` and `HDF_CDROM_CUE=8` preserve the selected extension without changing the saved configuration layout.
- ISO and supported BIN/CUE data tracks are read-only. CUE supports relative backing paths and multiple BIN files. CD audio playback, raw READ CD and CD32-specific CD-ROM behavior are not implemented. AmigaOS needs a compatible CD-ROM driver/filesystem; native tests do not establish guest-driver compatibility.
- Keep cached ATA capacity equal to the full backing sector count (plus the synthetic-RDB prefix where applicable). Round calculated CHS up to cover a partial last cylinder; do not truncate capacity to whole cylinders. IDENTIFY must report the actual capacity. The 201 MiB PFS3 regression image has 411648 sectors: block 411647 must remain accessible; block 411648 must fail.
- Capacity calculations belong at open/remount, not in each transfer. `HDD_DISABLE_READ_RANGE_CHECK` is intentionally undefined in production; the test suite alone builds an alternate variant with it enabled. Writes and hardfile seek-index guards remain checked.
- Keep seek indexes bounded to 1024 entries and use sector offsets to avoid byte-offset overflow near 4 GiB. Checked FAT seeks use absolute 512-byte sector offsets. Propagate checked FAT/quiet SD I/O errors without invoking fatal legacy paths. Do not seek beyond EOF after a successful final-sector read/write. Patch sector-zero RDB flags/checksum only after checking the `RDSK` signature.
- ATA multiple mode supports 1/2/4/8/16 sectors, starts disabled, and accepts zero to disable it. Invalid settings return ABRT while preserving the previous valid mode; IDENTIFY reports the maximum and current setting.
- ATA buffer waits have a 2-second timeout. Reset/replacement cancellation uses the command generation captured with the task file and HDL busy metadata. Cancelled handlers must not publish stale status/errors or commit subsequent write sectors. Direct reads observe cancellation between storage chunks.
- `rtl/minimig/ide.v` and firmware must agree on odd-byte packet rounding, intermediate/final completion, status-bit-6 FIFO/PIO abort, and generation/busy metadata in SPI taskfile word 7. Protocol changes require matching firmware/HDL and the IDE bench; rebuild the HDL when its RTL changes. Prefer fixing a demonstrated HDL issue over a firmware workaround. Preserve all original author notices when adapting MiST code.

### Stack and Build Constraints

The controller has only **0x1000 bytes (4 KiB) of stack**, with `_STACKTOP=0x1000`. Stack accesses are faster than general memory on this target, but check nested call frames before moving buffers. Temporary HDD buffers are local: IDENTIFY allocates its 512 bytes inside its handler, task-file/filename buffers are local, and sector buffers are 512 bytes. In `cdrom.c`, the 12-byte packet and 512-byte IDENTIFY response are local, while the 2048-byte transfer buffer and media state must survive cooperative polls. In `cdrom_image.c`, `read_bytes()` uses a local 512-byte sector buffer; keep the parser buffers/file structures and persistent seek cache static. Moving all parser scratch space onto the stack is unsafe without a complete budget check: it adds about 2.1 KiB, and nested FAT file opening already uses a 1 KiB buffer.

Firmware header dependencies are incomplete. After structure-layout/header changes that affect callers, force a rebuild with `make -B -o 832obj -C fw/ctrl_832 832OSDU0.bin` (after a normal build has created `832obj`). Plain `make -B` attempts to recreate that existing directory. Preserve CRLF source files; use `git -c core.whitespace=cr-at-eol diff --check` where needed. The firmware formatter is limited: avoid relying on `%.16s` for OSD filename truncation; use explicit bounded copies.

### Storage Regression Locations

- `fw/ctrl_832/tests/`: native C tests for image/ATAPI behavior, FAT, HDD bounds/indexing/multiple mode/cancellation and quiet SD errors. The suite runs both read-range-check variants. Requires a host C compiler, not Icarus Verilog; products go to `/tmp/minimig-fw-tests`. ASan/UBSan are enabled; leak detection is disabled for ptraced environments. The existing configuration-title test has separate instructions in `fw/ctrl_832/docs/CONFIGURATION_TITLES.md`.
- `bench/ide/`: `ide_packet_tb.v` tests the production IDE/FIFO RTL without running firmware. Keep it here rather than under firmware tests. Requires Icarus Verilog; products go to `/tmp/minimig-ide-tests`.
- Keep both test READMEs and `bench/README.md` current when relocating tests. Board timing and Amiga driver validation remain separate from these regressions.

## Commit & Pull Request Guidelines

History uses short, imperative subjects such as `optimize timing in rtg`. PRs should explain the problem, implementation and validation; identify tested boards and raster profiles, link relevant issues, and disclose remaining timing failures. Include screenshots for visible OSD/video changes when helpful. Avoid unrelated submodule changes and generated build artifacts.
