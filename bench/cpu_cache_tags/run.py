#!/usr/bin/env python3
"""Run with python3 bench/cpu_cache_tags/run.py; requires Icarus Verilog."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="cpu-cache-tags-") as work:
    executable = Path(work) / "tags"
    subprocess.run([
        "iverilog", "-g2012", "-DSOC_SIM", "-s", "cpu_cache_tags_tb",
        "-o", str(executable),
        str(root / "bench/cpu_cache_tags/cpu_cache_tags_tb.v"),
        str(root / "cpu_cache_new.v"),
        str(root / "rtl/sdram/dpram_inf_256x32.v"),
        str(root / "rtl/sdram/dpram_inf_be_1024x32.v"),
    ], check=True)
    subprocess.run(["vvp", str(executable)], check=True)
