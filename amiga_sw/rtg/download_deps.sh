#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
deps_dir=${2:-"$script_dir/.deps"}
mkdir -p "$deps_dir"

fetch() {
    local url=$1 archive=$2
    if [[ ! -s "$deps_dir/$archive" ]]; then
        echo "Downloading $archive"
        curl --fail --location --silent --show-error --retry 2 \
            --connect-timeout 15 --max-time 120 "$url" \
            -o "$deps_dir/$archive.part"
        mv -- "$deps_dir/$archive.part" "$deps_dir/$archive"
    fi
}

ndk() {
    fetch 'https://os.amigaworld.de/download.php?id=3' NDK39.lha
    7z x -y "-o$deps_dir" "$deps_dir/NDK39.lha" 'NDK_3.9/Include/*' > /dev/null
    test -f "$deps_dir/NDK_3.9/Include/include_i/hardware/custom.i"
    for lib in exec intuition expansion graphics; do
        test -f "$deps_dir/NDK_3.9/Include/fd/${lib}_lib.fd"
    done
}

public() {
    fetch 'https://wiki.icomp.de/w/images/6/62/P96Develop.lha' P96Develop.lha
    7z x -y "-o$deps_dir" "$deps_dir/P96Develop.lha" \
        'Picasso96Develop/Include/libraries/Picasso96.i' > /dev/null
    test -f "$deps_dir/Picasso96Develop/Include/libraries/Picasso96.i"
}

private() {
    fetch 'https://wiki.icomp.de/w/images/7/70/P96CardDevelop.lha' P96CardDevelop.lha
    7z x -y "-o$deps_dir" "$deps_dir/P96CardDevelop.lha" \
        'Picasso96Develop/PrivateInclude/*' > /dev/null
    test -f "$deps_dir/Picasso96Develop/PrivateInclude/boardinfo.i"
    test -f "$deps_dir/Picasso96Develop/PrivateInclude/settings.i"
    # vasm's Motorola syntax treats operand spaces as comments. Normalize
    # these tag expressions without changing their numeric values.
    python3 - "$deps_dir/Picasso96Develop/PrivateInclude/boardinfo.i" <<'PYCODE'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = re.sub(r"(ABMA_\w+\s+equ\s+)\((TAG_USER\s*\+\s*32\s*\+\s*\$[0-9a-fA-F]+)\)",
           lambda m: m[1] + "(" + re.sub(r"\s+", "", m[2]) + ")", s)
p.write_text(s)
PYCODE
}

case ${1:-all} in
    ndk) ndk ;;
    public) public ;;
    private) private ;;
    all) ndk; public; private ;;
    *) echo "Usage: $0 [all|ndk|public|private] [destination]" >&2; exit 2 ;;
esac
