#!/usr/bin/env python3
"""Generate assembler library vector offsets from an Amiga NDK FD file."""
from pathlib import Path
import re
import sys

source, target = map(Path, sys.argv[1:])
offset = None
lines = [f"; Generated from {source.name}; do not edit."]
for raw in source.read_text().splitlines():
    line = raw.strip()
    if line.startswith("##bias "):
        offset = int(line.split()[1])
    elif line == "##end":
        break
    elif line and not line.startswith(("*", "#")):
        name = line.split("(", 1)[0]
        if offset is None or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise ValueError(f"Invalid FD definition: {line}")
        # Private entries also occupy vectors and must advance the offset.
        lines.append(f"_LVO{name} equ -{offset}")
        offset += 6

target.parent.mkdir(parents=True, exist_ok=True)
target.write_text("\n".join(lines) + "\n")
