############################################
# set Clock
############################################
set CYCLE  1.0
set CYCLE2 5.0

## Do not modify the following lines ##
create_clock -name "i_clk"  -period $CYCLE  [get_ports i_clk ]
create_clock -name "i_clk2" -period $CYCLE2 [get_ports i_clk2]

set_dont_touch_network      [get_clocks *]
set_fix_hold                [get_clocks *]
set_ideal_network           [get_ports i_clk*]
set_clock_uncertainty  0.1  [get_clocks *]
set_clock_latency      0.5  [get_clocks *]
set_clock_transition   0.1  [get_clocks *]

set_input_delay  0.5 -clock i_clk [remove_from_collection [all_inputs] [get_ports i_clk*]]
set_output_delay 0.5 -clock i_clk [all_outputs]

set_drive 1    [all_inputs]
set_load  0.05 [all_outputs]
## Do not modify the above lines ##

# Add your Clock Domain Crossing constraint here
# Hint: set_false_path or set_clock_group
