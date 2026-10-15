#!/usr/bin/env python3
"""Generate isolated RTG experiments and compare Yosys ECP5 resource counts.

Working RTL is read only. Variant RTL, diffs, simulation logs and mapped
netlists are written under --output (default /tmp/rtg-area-assessment).
"""
import argparse
import concurrent.futures
import difflib
import json
import hashlib
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"Expected one occurrence of {old!r}, found {source.count(old)}")
    return source.replace(old, new, 1)


def simplify_fetch(video):
    # All supported rows/sections and the prefill limit are multiples of eight
    # words. Preserve the >=8 check for other parameterizations.
    video = replace_once(video,
        "wire [19:0] remaining = limit_words > issued ? limit_words-issued : 20'd0;",
        "wire [19:0] remaining = limit_words - issued;\n"
        "    wire more_words = issued < limit_words;")
    return replace_once(video, "remaining >= 8 && used < 480;",
        "more_words && (H_ACTIVE % 16 == 0 || remaining >= 8) && used < 480;")


def burst_counts(video):
    # Isolated from simplify_fetch: retain the original clamp/request form.
    video = replace_once(video,
        "reg [19:0] top_words, bottom_words, issued_top, issued_bottom;",
        "localparam COUNT_BITS = $clog2(H_ACTIVE * V_ACTIVE / 8 + 1);\n"
        "    reg [COUNT_BITS-1:0] top_words, bottom_words, issued_top, issued_bottom;")
    video = video.replace("wire [19:0]", "wire [COUNT_BITS-1:0]")
    video = video.replace("top_words < 256 ? top_words : 20'd256",
        "H_ACTIVE >= 512 ? 32 : (top_words < 32 ? top_words : 32)")
    video = video.replace("bottom_words < 256 ? bottom_words : 20'd256",
        "H_ACTIVE >= 512 ? 32 : (bottom_words < 32 ? bottom_words : 32)")
    video = video.replace("20'd0", "{COUNT_BITS{1'b0}}")
    video = video.replace("remaining >= 8", "remaining >= 1")
    video = video.replace("remaining > 32", "remaining > 4")
    video = video.replace("issued_bottom + 8", "issued_bottom + 1'b1")
    video = video.replace("issued_top + 8", "issued_top + 1'b1")
    video = video.replace("{10'd0,used_top} >= top_prefill", "used_top >= {top_prefill,3'd0}")
    video = video.replace("{10'd0,used_bottom} >= bottom_prefill", "used_bottom >= {bottom_prefill,3'd0}")
    video = replace_once(video, "{5'd0,issued,1'b0}",
        "{{(26-COUNT_BITS-4){1'b0}},issued,4'd0}")
    video = video.replace("(split_row * H_ACTIVE)/2 : split_row * H_ACTIVE",
        "(split_row * H_ACTIVE)/16 : (split_row * H_ACTIVE)/8")
    video = video.replace("((V_ACTIVE-split_row)*H_ACTIVE)/2 : (V_ACTIVE-split_row)*H_ACTIVE",
        "((V_ACTIVE-split_row)*H_ACTIVE)/16 : ((V_ACTIVE-split_row)*H_ACTIVE)/8")
    video = video.replace("(V_ACTIVE*H_ACTIVE)/2 : V_ACTIVE*H_ACTIVE",
        "(V_ACTIVE*H_ACTIVE)/16 : (V_ACTIVE*H_ACTIVE)/8")
    video = video.replace("wire [COUNT_BITS-1:0] issued =", "// Transfer counters/limits below count eight-word SDRAM bursts.\n"
                          "    wire [COUNT_BITS-1:0] issued =")
    return video


def shared_memory(video, fifo):
    control = fifo.replace("module rtg_async_fifo #(", "module rtg_fifo_control #(")
    control = replace_once(control, "input wr_en, input [DATA_BITS-1:0] wr_data,", "input wr_en,")
    control = replace_once(control, "input rd_en, output reg [DATA_BITS-1:0] rd_data,",
        "input rd_en,\n    output [ADDR_BITS-1:0] wr_addr, rd_addr,\n    output wr_accept, rd_accept,")
    control = replace_once(control,
        '    reg [DATA_BITS-1:0] ram [0:(1<<ADDR_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;\n', "")
    control = control[:control.index("    always @(posedge wr_clk)\n")] + """    assign wr_addr = wr_bin[ADDR_BITS-1:0];
    assign rd_addr = rd_bin[ADDR_BITS-1:0];
    assign wr_accept = !wr_reset_busy && wr_en && !full;
    assign rd_accept = !rd_reset_busy && rd_en && !empty;
endmodule
"""
    video = replace_once(video, "    rtg_async_fifo top_fifo (", """    // One physical EBR, two independently managed 512-word FIFO banks.
    wire [8:0] top_wr_addr, bottom_wr_addr, top_rd_addr, bottom_rd_addr;
    wire write_top, write_bottom, read_top, read_bottom;
    reg [15:0] shared_ram [0:1023] /* synthesis syn_ramstyle="block_ram" */;
    reg [15:0] shared_rd_data;
    assign data_top = shared_rd_data;
    assign data_bottom = shared_rd_data;
    always @(posedge clk_114)
        if (write_top || write_bottom)
            shared_ram[{owner, owner ? bottom_wr_addr : top_wr_addr}] <= fetch_d;
    always @(posedge clk_rtg)
        if (read_top || read_bottom)
            shared_rd_data <= shared_ram[{selected_bottom, selected_bottom ? bottom_rd_addr : top_rd_addr}];

    rtg_fifo_control top_fifo (""")
    video = video.replace("rtg_async_fifo bottom_fifo (", "rtg_fifo_control bottom_fifo (")
    video = video.replace(".wr_data(fetch_d),", "")
    for bank in ("top", "bottom"):
        video = replace_once(video, f".rd_en(pop_{bank}),.rd_data(data_{bank}),",
            f".rd_en(pop_{bank}),.wr_addr({bank}_wr_addr),.rd_addr({bank}_rd_addr),"
            f".wr_accept(write_{bank}),.rd_accept(read_{bank}),")
    return video, control


def read_source(name, baseline_ref=None):
    if baseline_ref:
        return subprocess.check_output(["git", "show", f"{baseline_ref}:{name}"], cwd=ROOT, text=True)
    return (ROOT / name).read_text()


def make_variants(out, baseline_ref=None):
    original_video = read_source("rtl/rtg/rtg_video.v", baseline_ref)
    original_fifo = read_source("rtl/rtg/rtg_async_fifo.v", baseline_ref)
    video1 = simplify_fetch(original_video)
    video2 = burst_counts(original_video)
    video12 = burst_counts(video1).replace("remaining >= 8", "remaining >= 1")
    video3, fifo3 = shared_memory(original_video, original_fifo)
    video23, fifo23 = shared_memory(video2, original_fifo)
    video123, fifo123 = shared_memory(video12, original_fifo)
    variants = {
        "baseline": (original_video, original_fifo),
        "1_fetch": (video1, original_fifo),
        "2_bursts": (video2, original_fifo),
        "3_shared_ram": (video3, fifo3),
        "12_fetch_bursts": (video12, original_fifo),
        "23_bursts_shared": (video23, fifo23),
        "123_all": (video123, fifo123),
    }
    for name, (video, fifo) in variants.items():
        directory = out / name
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "rtg_video.v").write_text(video)
        (directory / "rtg_async_fifo.v").write_text(fifo)
        patch = "".join(difflib.unified_diff(original_video.splitlines(True), video.splitlines(True),
                                           fromfile="a/rtl/rtg/rtg_video.v", tofile="b/rtl/rtg/rtg_video.v"))
        patch += "".join(difflib.unified_diff(original_fifo.splitlines(True), fifo.splitlines(True),
                                            fromfile="a/rtl/rtg/rtg_async_fifo.v", tofile="b/rtl/rtg/rtg_async_fifo.v"))
        (directory / "changes.patch").write_text(patch)
    # The checked-in RTL currently captures events in clk_rtg; adapt only the
    # temporary bench copy to its current interface, without changing the RTL.
    tb = (ROOT / "bench/rtg_hdmi/rtg_video_tb.v").read_text()
    if not re.search(r"\binput[^;\n]*\bclk_pixel\b", original_video):
        tb = re.sub(r"\.clk_pixel\([^)]*\),", "", tb)
    (out / "rtg_video_tb.v").write_text(tb)
    tb = tb.replace("W=64,H=12,HT=96,VT=24", "W=1024,H=12,HT=1344,VT=24")
    tb = tb.replace("#10000000;", "#30000000;")
    (out / "rtg_video_wide_tb.v").write_text(tb)
    return variants


def run_command(command, log):
    with log.open("w") as f:
        result = subprocess.run(command, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")


def assess_one(name, out):
    directory = out / name
    sources = [str(directory / "rtg_video.v"), str(directory / "rtg_async_fifo.v")]
    for bench in ("rtg_video_tb", "rtg_video_wide_tb"):
        exe = directory / bench
        run_command(["iverilog", "-g2012", "-s", "rtg_video_tb", "-o", str(exe),
                     str(out / (bench + ".v"))] + sources, directory / (bench + "_compile.log"))
        run_command(["vvp", str(exe)], directory / (bench + ".log"))
    print(f"{name}: pixel/format/split/reset/underflow simulations PASS", flush=True)
    script = (f"read_verilog {' '.join(sources)}; "
              f"synth_ecp5 -top rtg_video -json {directory / 'netlist.json'}; stat")
    run_command(["yosys", "-Q", "-T", "-p", script], directory / "yosys.log")
    cells = json.loads((directory / "netlist.json").read_text())["modules"]["rtg_video"]["cells"]
    counts = {}
    for cell in cells.values():
        counts[cell["type"]] = counts.get(cell["type"], 0) + 1
    result = {
        "LUT4": counts.get("LUT4", 0), "CCU2C": counts.get("CCU2C", 0),
        "FF": counts.get("TRELLIS_FF", 0), "EBR": counts.get("DP16KD", 0),
        "PFUMX": counts.get("PFUMX", 0), "L6MUX21": counts.get("L6MUX21", 0),
        "all_cells": counts,
    }
    (directory / "counts.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{name}: synthesis PASS { {k:v for k,v in result.items() if k != 'all_cells'} }", flush=True)
    return name, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/rtg-area-assessment"))
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--variants", nargs="+", help="Run only the named variants")
    parser.add_argument("--baseline-ref", help="Read the original RTL from a Git revision")
    args = parser.parse_args()
    args.output = args.output.resolve()
    source_hashes = {name: hashlib.sha256(read_source(name, args.baseline_ref).encode()).hexdigest()
                     for name in ("rtl/rtg/rtg_video.v", "rtl/rtg/rtg_async_fifo.v")}
    metadata_file = args.output / "metadata.json"
    if args.variants and metadata_file.exists():
        old_metadata = json.loads(metadata_file.read_text())
        if old_metadata.get("source_sha256") != source_hashes:
            parser.error("RTL changed since the previous run; use a fresh output directory or run all variants")
    variants = make_variants(args.output, args.baseline_ref)
    metadata = {
        "yosys": subprocess.check_output(["yosys", "-V"], text=True).strip(),
        "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "baseline_ref": args.baseline_ref,
        "top": "rtg_video",
        "parameters": {"H_ACTIVE": 1024, "V_ACTIVE": 768, "H_TOTAL": 1344,
                       "V_TOTAL": 806, "PREPARE_DELAY": 4096},
        "source_sha256": source_hashes,
        "synthesis": "synth_ecp5 -top rtg_video (default options)",
    }
    metadata_file.write_text(json.dumps(metadata, indent=2) + "\n")
    run_command(["yosys", "-Q", "-T", "-p",
                 "read_verilog bench/rtg_area/fetch_equivalence.v; prep -top fetch_equivalence; "
                 "sat -verify -prove match 1 -show-inputs"], args.output / "fetch_equivalence.log")
    print("Burst-aligned fetch/address equivalence: PASS", flush=True)
    selected = args.variants or list(variants)
    if any(name not in variants for name in selected):
        parser.error("Unknown variant")
    result_file = args.output / "results.json"
    results = json.loads(result_file.read_text()) if args.variants and result_file.exists() else {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs = [pool.submit(assess_one, name, args.output) for name in selected]
        for future in concurrent.futures.as_completed(jobs):
            name, result = future.result()
            results[name] = result
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print("\nvariant                  LUT4  CCU2C    FF   EBR  PFUMX L6MUX21")
    for name in variants:
        if name not in results:
            continue
        r = results[name]
        print(f"{name:24} " + " ".join(f"{r[k]:5}" for k in ("LUT4", "CCU2C", "FF", "EBR", "PFUMX", "L6MUX21")))


if __name__ == "__main__":
    main()
