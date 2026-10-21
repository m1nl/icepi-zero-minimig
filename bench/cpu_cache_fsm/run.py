#!/usr/bin/env python3
"""Check both FSM variants; run python3 bench/cpu_cache_fsm/run.py."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--variant', choices=('root', 'small', 'all'), default='small')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="cpu-cache-fsm-") as work:
    for variant, source in (("root", root / "cpu_cache_new.v"),
                            ("small", root / "rtl/sdram/cpu_cache_small.v")):
        if args.variant not in ('all', variant):
            continue
        for legacy in ((0, 1) if variant == "small" else (0,)):
            executable = Path(work) / f"{variant}-{legacy}"
            subprocess.run([
                "iverilog", "-g2012", "-DSOC_SIM", *(["-DSMALL_CACHE"] if variant == "small" else []),
                "-s", "cpu_cache_fsm_tb", "-o", str(executable),
                f"-Pcpu_cache_fsm_tb.LEGACY_WRITE_COMBINE={legacy}",
                str(root / "bench/cpu_cache_fsm/cpu_cache_fsm_tb.v"), str(source),
                str(root / "rtl/sdram/dpram_inf_256x32.v"),
                str(root / "rtl/sdram/dpram_inf_be_1024x32.v"),
            ], check=True)
            print(f"{variant} legacy_write_combine={legacy}:", flush=True)
            subprocess.run(["vvp", str(executable)], check=True)
