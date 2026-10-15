#!/usr/bin/env bash
# Shared TG68K/RTG simulation; no driver headers are needed for MMIO alone.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 amiga_sw/rtg/tests/run.py --mmio-only "$@"
