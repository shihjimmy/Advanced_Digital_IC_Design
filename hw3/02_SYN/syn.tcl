set company {NTUGIEE}
set designer {student}

set verilogout_no_tri TRUE

set sh_enable_line_editing true
set sh_line_editing_mode emacs
history keep 100
alias h history

############################################
#  set libraries
############################################
set search_path " \
    /share1/tech/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/CCS/ \
    /share1/tech/ADFP/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/NLDM/ \
    $search_path .\
"

set target_library " \
    N16ADFP_StdCellss0p72vm40c_ccs.db \
    N16ADFP_StdCellff0p88v125c_ccs.db \
    N16ADFP_SRAM_ss0p72v0p72vm40c_100a.db \
    N16ADFP_SRAM_ff0p88v0p88v125c_100a.db \
"

set link_library "* $target_library dw_foundation.sldb"
set symbol_library "generic.sdb"
set synthetic_library "dw_foundation.sldb"

############################################
#  create path
############################################
sh mkdir -p Netlist
sh mkdir -p Report

############################################
#  import design
############################################
set DESIGN "keccak"

analyze -format verilog "filelist.v"
elaborate $DESIGN
current_design $DESIGN
link

############################################
#  global Setting
############################################
set_operating_conditions -max_library N16ADFP_StdCellss0p72vm40c_ccs -max ss0p72vm40c

############################################
#  set design constraints
############################################
source -echo -verbose ./$DESIGN.sdc

check_design > Report/check_design.txt
check_timing > Report/check_timing.txt

############################################
#  compile
############################################
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

#clock gating
set_clock_gating_style \
    -max_fanout 4 \
    -pos integrated \
    -control_point before \
    -control_signal scan_enable 

compile_ultra -scan -gate_clock
compile -only_hold_time -inc

############################################
#  output reports 
############################################
report_area   > Report/$DESIGN\_predft.area
report_timing > Report/$DESIGN\_predft.timing
report_timing -delay min -max_paths 5 > Report/$DESIGN\_predft.timing_min
report_timing -delay max -max_paths 5 > Report/$DESIGN\_predft.timing_max

report_clock_gating -gating_elements

############################################
#  add scan chain
############################################
# TODO
set test_default_scan_style multiplexed_flip_flop
set test_default_delay 0
set test_default_bidir_delay 0
set test_default_strobe 40
set test_default_period 100

create_test_protocol -infer_asynch -infer_clock
#report_constraint -all_violators
dft_drc

set_scan_configuration -chain_count 1
set_scan_configuration -create_dedicated_scan_out_ports true
preview_dft

insert_dft
#report_constraint -all_violators
dft_drc

compile -only_hold_time -inc

############################################
#  output reports 
############################################
report_area   > Report/$DESIGN\_syn.area
report_timing > Report/$DESIGN\_syn.timing
report_timing -delay min -max_paths 5 > Report/$DESIGN\_syn.timing_min
report_timing -delay max -max_paths 5 > Report/$DESIGN\_syn.timing_max
report_scan_path -view existing -chain all > Report/$DESIGN\_syn.scan_path
report_scan_path -view existing -cell all  > Report/$DESIGN\_syn.scan_cell

############################################
#  change naming rule
############################################
set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

############################################
#  output results
############################################
remove_unconnected_ports -blast_buses [get_cells -hierarchical *]
set verilogout_higher_designs_first true
write -format ddc     -hierarchy -output Netlist/$DESIGN\_syn.ddc
write -format verilog -hierarchy -output Netlist/$DESIGN\_syn.v
write_sdf -version 3.0 -context verilog -load_delay cell Netlist/$DESIGN\_syn.sdf
write_sdc -version 1.8 Netlist/$DESIGN\_syn.sdc 
write_scan_def      -output Netlist/$DESIGN\_syn.scandef
write_test_protocol -output Netlist/$DESIGN\_syn.spf

############################################
#  finish and quit 
############################################
report_timing
report_area

#exit
