#!/usr/bin/env python3
"""Compare total-counter variants from the recorded pre-removal Git baseline."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
METRICS = ("LUT4", "CCU2C", "TRELLIS_FF", "DP16KD", "PFUMX", "L6MUX21")


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError("Working RTL no longer matches: " + before)
    return source.replace(before, after, 1)


def run(command, log):
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream,
                                stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError("Command failed; see " + str(log))


def assess(name, source, fifo, baseline, out, simulate):
    folder = out / name
    folder.mkdir(exist_ok=True)
    video = folder / "rtg_video.v"
    video.write_text(source)
    (folder / "rtg_async_fifo.v").write_text(fifo)
    (folder / "change.patch").write_text("".join(difflib.unified_diff(
        baseline.splitlines(True), source.splitlines(True),
        fromfile="baseline/rtg_video.v", tofile=name + "/rtg_video.v")))
    script = (f'read_verilog "{video}" "{folder / "rtg_async_fifo.v"}"; '
              f'synth_ecp5 -top rtg_video -json "{folder / "netlist.json"}"; stat')
    run(["yosys", "-Q", "-T", "-p", script], folder / "yosys.log")
    cells = json.loads((folder / "netlist.json").read_text())["modules"]["rtg_video"]["cells"]
    counts = Counter(cell["type"] for cell in cells.values())
    result = {key: counts[key] for key in METRICS}
    if simulate:
        bench = (ROOT / "bench/rtg_hdmi/rtg_video_tb.v").read_text()
        for parameter in ("H_TOTAL", "V_TOTAL"):
            if not re.search(r"parameter\s+" + parameter + r"\b", source):
                bench = re.sub(r",\." + parameter + r"\([^)]*\)", "", bench)
        test = folder / "rtg_video_tb.v"
        test.write_text(bench)
        run(["verilator", "--binary", "--timing", "-Wno-fatal", "-DSOC_SIM",
             "--compiler", "gcc", "--output-split", "0", "--output-split-cfuncs", "0",
             "--top-module", "rtg_video_tb", "--Mdir", str(folder / "sim"),
             str(test), str(video), str(folder / "rtg_async_fifo.v")],
            folder / "compile.log")
        run([str(folder / "sim/Vrtg_video_tb")], folder / "simulation.log")
        result["simulation"] = "PASS"
    print(name + ": " + json.dumps(result), flush=True)
    return name, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/rtg-totals-assessment"))
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--simulate", action="store_true")
    parser.add_argument("--baseline-ref", default="5603d14da7e703b238aa377265c61cf815cf5148",
                        help="Git revision containing the original total parameters")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    baseline = subprocess.check_output(
        ["git", "show", args.baseline_ref + ":rtl/rtg/rtg_video.v"], cwd=ROOT, text=True)
    fifo = subprocess.check_output(
        ["git", "show", args.baseline_ref + ":rtl/rtg/rtg_async_fifo.v"], cwd=ROOT, text=True)
    h_removed = replace_once(baseline, "  parameter H_TOTAL = 1344,\n", "")
    totals_removed = replace_once(h_removed,
        "  parameter V_ACTIVE = 768,\n  parameter V_TOTAL = 806",
        "  parameter V_ACTIVE = 768")
    free_running = replace_once(totals_removed,
        "scan_row == V_TOTAL - 1 ? 10'd0 : scan_row + 1'b1", "scan_row + 1'b1")
    active_rows = replace_once(free_running,
        "if (line_prepare) begin", "if (line_prepare && frame_active) begin")
    variants = {"baseline": baseline, "h_total_removed": h_removed,
                "totals_free_running": free_running, "totals_active_rows": active_rows}
    metadata = {"baseline_ref": args.baseline_ref,
                "yosys": subprocess.check_output(["yosys", "-V"], text=True).strip(),
                "rtg_sha256": hashlib.sha256(baseline.encode()).hexdigest(),
                "fifo_sha256": hashlib.sha256(fifo.encode()).hexdigest(),
                "raster": "1024x768, 1344x806 total; default production parameters",
                "synthesis": "synth_ecp5 -top rtg_video; includes FIFOs and palette"}
    (out / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    # Verilator's generated makefiles use ccache when it is installed.
    os.environ["CCACHE_DISABLE"] = "1"
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(assess, name, source, fifo, baseline, out, args.simulate)
                   for name, source in variants.items()]
        results = dict(future.result() for future in futures)
    (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
