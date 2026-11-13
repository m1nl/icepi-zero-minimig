# build.tcl — headless Lattice Diamond build

set proj "minimig_flea_e5.ldf"

prj_project open $proj

prj_run Export -impl Minimig_Flea_E5 -forceAll -task Bitgen

puts "=== Saving and closing ==="
# prj_project save
prj_project close

puts "=== Done ==="
