if {![is_project_open]} {
    if {[llength $quartus(args)] == 0} {
        post_message -type error "usage: quartus_sta -t report_recovery.tcl <project>"
        qexit -error
    }
    set project_name [lindex $quartus(args) 0]
    project_open -revision [get_current_revision $project_name] $project_name
}

if {![timing_netlist_exist]} {
    create_timing_netlist
    read_sdc
}

# The complete compile identified Slow 900 mV 0 C as the worst recovery
# corner. Reproduce that corner here so the report is deterministic.
set_operating_conditions -model slow -temperature 0 -voltage 900
update_timing_netlist

report_timing \
    -recovery \
    -npaths 2000 \
    -detail full_path \
    -file output_files/ddr4_dual_worst_recovery.rpt \
    -panel_name "DDR4 dual worst recovery paths"

project_close
