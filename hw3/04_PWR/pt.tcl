set company {NTUGIEE}
set designer {student}

set sh_enable_line_editing true
set sh_line_editing_mode emacs
history keep 100
alias h history

############################################
# set libraries
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

set link_library "* $target_library"

############################################
# import design
############################################
set DESIGN "keccak"

read_file -format verilog ../02_SYN/Netlist/$DESIGN\_syn.v
current_design $DESIGN
link

############################################
# source sdc
############################################
source -echo -verbose ../02_SYN/Netlist/$DESIGN\_syn.sdc

############################################
# read fsdb
############################################
set power_enable_analysis true


############################################
# power
############################################
read_vcd -strip_path testbench/u_$DESIGN ../03_GATE/$DESIGN\_00.vcd
update_power
report_power
report_power > $DESIGN\_m00.power



############################################
# power
############################################
read_vcd -strip_path testbench/u_$DESIGN ../03_GATE/$DESIGN\_01.vcd
update_power
report_power
report_power > $DESIGN\_m01.power



############################################
# power
############################################
read_vcd -strip_path testbench/u_$DESIGN ../03_GATE/$DESIGN\_11.vcd
update_power
report_power
report_power > $DESIGN\_m11.power
# report_power > $DESIGN\_m01.power
# report_power > $DESIGN\_m11.power
