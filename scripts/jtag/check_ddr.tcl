connect
after 1000
targets 2
source scripts/ps7_init.tcl
ps7_init
after 500

puts "=================================================================="
puts "  INSPECTING DDR3 SYSTEM STATE VIA JTAG                           "
puts "=================================================================="

puts "\n--- DDR3 Code Header @ 0x00100000 ---"
puts [mrd 0x00100000 4]

puts "\n--- Scratchpad @ 0x00500000 (Subword test result) ---"
puts [mrd 0x00500000 4]

puts "\n--- DDR3 Stack @ 0x00FFFF80 - 0x00FFFFFF ---"
puts [mrd 0x00FFFF80 16]
puts [mrd 0x00FFFFC0 16]







puts "\n--- font8x8 data at 0x0013d170 ---"
puts [mrd 0x0013d170 16]



puts "=================================================================="

