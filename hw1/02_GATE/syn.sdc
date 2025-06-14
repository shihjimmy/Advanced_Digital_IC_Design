############################################
# set Clock
############################################
set cycle 1.0

create_clock -period $cycle -name i_clk     [get_ports i_clk]
set_dont_touch_network                      [get_clocks i_clk]
set_fix_hold                                [get_clocks i_clk]
set_ideal_network                           [get_ports i_clk]
set_clock_uncertainty -hold 0.005           [get_clocks i_clk]
set_clock_uncertainty -setup 0.1            [get_clocks i_clk]
set_clock_latency 0.5                       [get_clocks i_clk]

############################################
# set max delay from input to output
############################################
set MAX_Delay 0
set_max_delay $MAX_Delay -from [all_inputs] -to [all_outputs]

############################################
# input drive and output load
############################################
set_drive 1 [all_inputs]
set_load 0.05 [all_outputs]

############################################
# set i/o delay
############################################
set_input_delay  [expr $cycle * 0.5] -clock i_clk [remove_from_collection [all_inputs] {i_clk}]
set_output_delay [expr $cycle * 0.5] -clock i_clk [all_outputs]
