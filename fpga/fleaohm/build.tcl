# build.tcl — headless Lattice Diamond build

set proj "minimig_fleaohm.ldf"

prj_project open $proj

prj_run Export -impl Minimig_FleaOhm -forceAll -task Bitgen

puts "=== Saving and closing ==="
# prj_project save
prj_project close

puts "=== Done ==="
