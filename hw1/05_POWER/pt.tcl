set company {NTUGIEE}
set designer {student}

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

set target_library "N16ADFP_StdCellff0p88v125c_ccs.db \
                    N16ADFP_StdIOff0p88v1p98v125c.db \
                    N16ADFP_SRAM_ff0p88v0p88v125c_100a.db \
                    "

set link_library "* $target_library"

############################################
# import design
############################################
set power_enable_analysis true
# if we use time_based, it can get precise result
# but it only support vcd file format
set power_analysis_mode time_based

set DESIGN "top"
read_file -format verilog "../02_GATE/Netlist/${DESIGN}_syn.v"
link
current_design $DESIGN

############################################
# source sdc 
############################################
# tell dc which is our clock / register
# or it will all be considered sequential 
source -echo -verbose "../02_GATE/Netlist/${DESIGN}_syn.sdc"


############################################
# power
############################################ 
read_vcd -strip_path testbench/u_${DESIGN} ${DESIGN}_p0.vcd
update_power
report_power
report_power > p0.power

############################################
# power
############################################
read_vcd -strip_path testbench/u_${DESIGN} ${DESIGN}_p1.vcd
update_power
report_power
report_power > p1.power

############################################
# power
############################################
read_vcd -strip_path testbench/u_${DESIGN} ${DESIGN}_p2.vcd
update_power
report_power
report_power > p2.power

############################################
# power
############################################
read_vcd -strip_path testbench/u_${DESIGN} ${DESIGN}_p3.vcd
update_power
report_power
report_power > p3.power

############################################
# power
############################################
read_vcd -strip_path testbench/u_${DESIGN} ${DESIGN}_p4.vcd
update_power
report_power
report_power > p4.power

