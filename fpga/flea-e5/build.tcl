# build.tcl — headless Lattice Diamond build

set proj "minimig_flea_e5.ldf"

prj_project open $proj

# Validate clock sources and applied exceptions before spending time on PAR.
prj_run Map -impl Minimig_Flea_E5 -forceAll
puts [exec python3 check_clocks.py --impl-dir Minimig_Flea_E5]
prj_run Export -impl Minimig_Flea_E5 -task Bitgen

puts "=== Saving and closing ==="
# prj_project save
prj_project close

puts "=== Done ==="
