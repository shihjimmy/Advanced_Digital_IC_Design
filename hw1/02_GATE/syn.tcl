set company {NTUGIEE}
set designer {student}

# set hdlin_translate_off_ship_text "TRUE"
# set edifout_netlist_only "TRUE"
set verilogout_no_tri TRUE

# set hdlin_enable_presto_for_vhdl "TRUE"
set sh_enable_line_editing true
set sh_line_editing_mode emacs
history keep 100
alias h history

############################################
# set libraries
############################################
set search_path    "/share1/tech/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/CCS/ \
                    /share1/tech/ADFP/Executable_Package/Collaterals/IP/stdio/N16ADFP_StdIO/NLDM/ \
                    /share1/tech/ADFP/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/NLDM/ \
                    $search_path .\
                    "

set target_library "N16ADFP_StdCellss0p72vm40c_ccs.db \
                    N16ADFP_StdIOss0p72v1p62vm40c.db \
                    N16ADFP_SRAM_ss0p72v0p72vm40c_100a.db \
                    "

set link_library "* $target_library dw_foundation.sldb"
set symbol_library "generic.sdb"
set synthetic_library "dw_foundation.sldb"

############################################
# create path
############################################
sh mkdir -p Netlist
sh mkdir -p Report

############################################
# import design
############################################
set DESIGN "top"

analyze -format verilog "../01_RTL/top.v"

elaborate $DESIGN
link
current_design $DESIGN

############################################
# source sdc
############################################
source -echo -verbose ./syn.sdc

check_design > Report/check_design.txt
check_timing > Report/check_timing.txt

############################################
# compile
############################################
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

############################################
# low power
############################################
set UPF_PATH "../04_UPF/top.rtl.upf"
set UPF_PATH_SYN "../04_UPF/top.syn.upf"
load_upf $UPF_PATH

set_voltage 0.72 -object_list {VDD VVDD_RLE}
set_voltage 0.0  -object_list {VSS}

compile_ultra
compile_ultra -inc
compile -inc -only_hold_time

############################################
# report output
############################################
current_design $DESIGN
report_timing > Report/${DESIGN}_syn.timing
report_area   > Report/${DESIGN}_syn.area

############################################
# output design
############################################
current_design $DESIGN

set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true

change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

remove_unconnected_ports -blast buses [get_cells -hierarchical *]
set verilogout_higher_designs_first true
write -format ddc      -hierarchy -output "./Netlist/${DESIGN}_syn.ddc"
write -format verilog  -hierarchy -output "./Netlist/${DESIGN}_syn.v"
write_sdf -version 3.0 -context verilog ./Netlist/${DESIGN}_syn.sdf
write_sdc ./Netlist/${DESIGN}_syn.sdc -version 1.8

save_upf $UPF_PATH_SYN

report_timing
report_area

    