#!/usr/bin/env python3
"""Compare working countdown RTL with the previously measured burst controller.

Generate a golden controller from the original Git baseline plus change 2.
Compare SDRAM request/priority/address and pixels every cycle, synthesize both
for ECP5, and leave all generated files outside production RTL.
"""
import argparse
import json
from pathlib import Path
import re
from assess import ROOT, read_source, burst_counts, run_command


def make_bench(source, output, wide=False, boundary=False):
    source = re.sub(r"\.clk_pixel\([^)]*\),", "", source)
    if wide:
        source = source.replace("W=64,H=12,HT=96,VT=24", "W=1024,H=12,HT=1344,VT=24")
        source = source.replace("#10000000;", "#30000000;")
    if boundary:
        source = source.replace("26'h10000", "26'h1ffff0").replace("26'h20000", "26'h3fffff0")
        source = source.replace("write_reg(0,1);write_reg(2,0);write_reg(8,2);write_reg(10,0);",
            "write_reg(0,16'h001f);write_reg(2,16'hfff0);write_reg(8,16'h03ff);write_reg(10,16'hfff0);")
    start = source.index("    rtg_video #(")
    end = source.index("    function ", start)
    inst = source[start:end].replace("rtg_video #(", "rtg_video_before #(", 1).replace(" dut (", " golden (", 1)
    inst = inst.replace(".fetch_addr(addr),.fetch_req(req),.fetch_pri(pri)",
        ".fetch_addr(golden_addr),.fetch_req(golden_req),.fetch_pri(golden_pri)")
    inst = inst.replace(".red(r),.green(g),.blue(b),.pixel(pixel),.de(de)",
        ".red(golden_r),.green(golden_g),.blue(golden_b),.pixel(golden_pixel),.de(golden_de)")
    extra = """    wire [25:0] golden_addr;
    wire golden_req, golden_pri, golden_pixel, golden_de;
    wire [7:0] golden_r, golden_g, golden_b;
""" + inst + """    always @(negedge sys) if(reset_n) begin
        #1;
        if({req,pri,addr} !== {golden_req,golden_pri,golden_addr})
            $fatal(1,"countdown/golden SDRAM interface differs");
    end
    always @(negedge vid) if(reset_n) begin
        #1;
        if({de,pixel,r,g,b} !== {golden_de,golden_pixel,golden_r,golden_g,golden_b})
            $fatal(1,"countdown/golden pixel interface differs");
    end
"""
    output.write_text(source[:end] + extra + source[end:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", default="58d2d6a")
    parser.add_argument("--output", type=Path, default=Path("/tmp/rtg-countdown-check"))
    parser.add_argument("--skip-synthesis", action="store_true")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    before = burst_counts(read_source("rtl/rtg/rtg_video.v", args.baseline_ref))
    (out / "before.v").write_text(before)
    (out / "golden.v").write_text(before.replace("module rtg_video #(", "module rtg_video_before #(", 1))
    (out / "after.v").write_text((ROOT / "rtl/rtg/rtg_video.v").read_text())
    (out / "fifo.v").write_text((ROOT / "rtl/rtg/rtg_async_fifo.v").read_text())
    template = (ROOT / "bench/rtg_hdmi/rtg_video_tb.v").read_text()
    for name, wide, boundary in (("small", False, False), ("wide", True, False), ("boundary", False, True)):
        bench = out / (name + ".v")
        exe = out / name
        make_bench(template, bench, wide, boundary)
        run_command(["iverilog", "-g2012", "-s", "rtg_video_tb", "-o", str(exe),
                     str(bench), str(out / "golden.v"), str(out / "after.v"), str(out / "fifo.v")],
                    out / (name + "_compile.log"))
        run_command(["vvp", str(exe)], out / (name + ".log"))
        print(name + ": cycle-by-cycle SDRAM/pixel comparison PASS", flush=True)
    if args.skip_synthesis:
        return
    results = {}
    for name in ("before", "after"):
        script = (f"read_verilog {json.dumps(str(out / (name + '.v')))} {json.dumps(str(out / 'fifo.v'))}; "
                  f"synth_ecp5 -top rtg_video -json {json.dumps(str(out / (name + '.json')))}; stat")
        run_command(["yosys", "-Q", "-T", "-p", script], out / (name + "_yosys.log"))
        counts = {}
        for cell in json.loads((out / (name + ".json")).read_text())["modules"]["rtg_video"]["cells"].values():
            counts[cell["type"]] = counts.get(cell["type"], 0) + 1
        results[name] = counts
        print(name, {k: counts.get(k, 0) for k in ("LUT4", "CCU2C", "TRELLIS_FF", "DP16KD", "PFUMX", "L6MUX21")}, flush=True)
    (out / "counts.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
