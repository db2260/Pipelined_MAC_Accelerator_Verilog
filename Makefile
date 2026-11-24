sim:
	iverilog -g2012 -o sim.out rtl/mac_pipe.v tb/tb_mac_pipe.v && vvp sim.out
clean:
	rm -f sim.out
