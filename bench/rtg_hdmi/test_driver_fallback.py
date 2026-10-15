#!/usr/bin/env python3
"""Compatibility entry point; driver tests live in amiga_sw/rtg/tests/."""
from pathlib import Path
import runpy
import sys

tests = Path(__file__).resolve().parents[2] / 'amiga_sw/rtg/tests'
sys.path.insert(0, str(tests))
runpy.run_path(str(tests / 'test_driver_fallback.py'), run_name='__main__')
