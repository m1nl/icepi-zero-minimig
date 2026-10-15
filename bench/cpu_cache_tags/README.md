# Historical cache tag checks

`run.py` and `cpu_cache_tags_tb.v` target an earlier root-level `cpu_cache_new.v`
with `sdr_read_pre` and parameterized tag-slot comparisons. The current root
source no longer matches that interface, so this test fails elaboration and is
not part of the current regression. It is retained for reference.

Use `python3 bench/cpu_cache_fsm/run.py` for the currently passing small-cache
FSM/protocol test. Earlier tag-test fixtures are in `../archive/cpu-cache-review/`.
