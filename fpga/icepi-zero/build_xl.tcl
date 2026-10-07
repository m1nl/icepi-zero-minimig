# build.tcl — headless Lattice Diamond build

set proj "minimig_icepi-zero-xl.ldf"

prj_project open $proj

prj_run Export -impl Minimig_IcePi-Zero-XL -forceAll -task Bitgen

puts "=== Saving and closing ==="
# prj_project save
prj_project close

puts "=== Done ==="
puts "You can now e.g. run 'openFPGALoader -b icepi-zero Minimig_IcePi-Zero-XL/minimig_icepi-zero_Minimig_IcePi-Zero-XL.bit'"
