# Basys 3 / Artix-7: 100 MHz target. Tighten (e.g. 4.0) to find Fmax.
create_clock -period 10.000 -name clk [get_ports clk]
