refresh_connections

foreach service_type {device issp master jtag_debug processor monitor} {
    if {[catch {set paths [get_service_paths $service_type]} error_text]} {
        puts "$service_type: unsupported ($error_text)"
    } else {
        puts "$service_type: $paths"
    }
}
