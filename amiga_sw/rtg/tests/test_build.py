#!/usr/bin/env python3
"""Build both drivers/ADFs and verify packaging, no-op rebuilds and DEBUG changes.

Unlike the simulated-core suite, this test rebuilds the normal output files.
It finishes with DEBUG=0 artifacts and requires installed vasm and xdftool.
"""
import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

DRIVER = Path(__file__).resolve().parents[1]
PROFILES = (
    ("minimig.card", "minimig-rtg.adf", "MinimigRTG"),
    ("minimig-720p.card", "minimig-rtg-720p.adf", "MinimigRTG720p"),
)
ARTIFACTS = ["rtgcheck", "minimig.card.lst", "minimig-720p.card.lst"]
ARTIFACTS += [name for card, adf, _ in PROFILES for name in (card, adf)]


def build(debug):
    subprocess.run(["make", "-C", str(DRIVER), "-j2", f"DEBUG={debug}"], check=True)


def hashes():
    return [hashlib.sha256((DRIVER / card).read_bytes()).hexdigest()
            for card, _, _ in PROFILES]


def check_images():
    tool = shlex.split(os.environ.get("XDFTOOL", "xdftool"))
    with tempfile.TemporaryDirectory(prefix="rtg-adf-check-") as temporary:
        for index, (card, adf, volume) in enumerate(PROFILES):
            image = DRIVER / adf
            assert image.stat().st_size == 880 * 1024, adf
            assert image.read_bytes()[:4] == b"DOS\0", adf
            listing = subprocess.check_output(tool + ["-r", str(image), "list"], text=True)
            assert listing.split()[0] == volume, listing
            for disk_path, source in (("Libs/Picasso96/minimig.card", card),
                                      ("rtgcheck", "rtgcheck"), ("README", "README")):
                extracted = Path(temporary) / f"{index}-{source}"
                subprocess.run(tool + ["-r", str(image), "read", disk_path, str(extracted)],
                               check=True)
                assert extracted.read_bytes() == (DRIVER / source).read_bytes(), disk_path
    print("PASS: distinct OFS volumes contain their correct driver, diagnostic and README", flush=True)


def main():
    build(0)
    normal = hashes()
    assert normal[0] != normal[1], "Raster profiles produced identical drivers"
    check_images()
    timestamps = [(DRIVER / name).stat().st_mtime_ns for name in ARTIFACTS]
    build(0)
    assert timestamps == [(DRIVER / name).stat().st_mtime_ns for name in ARTIFACTS], \
        "Unchanged build regenerated outputs"
    print("PASS: unchanged builds preserve all output timestamps", flush=True)
    try:
        build(1)
        assert all(a != b for a, b in zip(normal, hashes())), "DEBUG missed a profile"
        check_images()
    finally:
        build(0)
    assert hashes() == normal, "DEBUG=0 did not restore both release drivers"
    check_images()
    print("PASS: DEBUG changes rebuild both profiles/ADFs; release outputs restored", flush=True)


if __name__ == "__main__":
    main()
