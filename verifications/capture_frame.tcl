# Dump both DDR3 frame buffers through the JTAG to AXI Master, no arguments.
# Program the board in the Vivado Hardware Manager, then in the Tcl Console:
#   source <path>/verifications/capture_frame.tcl
# Writes buff_0_axi32.hex and buff_1_axi32.hex next to this script, then open
# ov7670_capture.ipynb and Run All. READ transactions only: no DDR writes,
# no reset_hw_axi, no camera trigger. The writer keeps running during the dump.

namespace eval ::capture_frame {
    variable out_dir [file dirname [file normalize [info script]]]
    # Must match BASE_0/BASE_1 in rtl/write_frame_exec.v and rtl/read_frame_exec.v.
    variable buffers {0 0x00000000 1 0x00096000}
    # 640x480 RGB444, one pixel per 16-bit word: 640*480*2 bytes / 4.
    variable frame_words 153600
    variable burst_words 128
}

# One INCR READ burst, returned in ascending address order. Vivado 2025.2
# presents burst DATA with the highest address first, so the words are reversed.
proc ::capture_frame::read_burst {hw_axi address count} {
    set txn [create_hw_axi_txn capture_frame_burst $hw_axi -force -type READ \
        -address [format %08X $address] -len $count -burst INCR]
    run_hw_axi $txn
    refresh_hw_axi $hw_axi
    set response [string toupper [string trim [get_property STATUS.RRESP $hw_axi]]]
    if {$response ni {OKAY EXOKAY}} {
        error [format {AXI READ failed: RRESP=%s at 0x%08X} $response $address]
    }
    set raw [get_property DATA $txn]
    regsub -all {[_[:space:]]} $raw "" raw
    regsub -nocase {^0x} $raw "" raw
    if {[string length $raw] != $count*8 || ![regexp {^[0-9a-fA-F]+$} $raw]} {
        error [format {Invalid DATA at 0x%08X: expected %d hex digits, got %d} \
            $address [expr {$count*8}] [string length $raw]]
    }
    set words {}
    for {set i 0} {$i < $count} {incr i} {
        lappend words [string toupper [string range $raw [expr {$i*8}] [expr {$i*8+7}]]]
    }
    return [lreverse $words]
}

# Save one buffer, one word per line. Written as .partial and renamed only
# after the last burst, so a failed dump never replaces a complete file.
proc ::capture_frame::dump {hw_axi id base} {
    variable out_dir
    variable frame_words
    variable burst_words
    set filename [file join $out_dir [format {buff_%d_axi32.hex} $id]]
    set partial "${filename}.partial"
    set handle [open $partial w]
    fconfigure $handle -encoding ascii -translation lf
    puts [format {buff_%d: 0x%08X, %d words -> %s} $id $base $frame_words $filename]
    set failed [catch {
        set done 0
        set bursts 0
        while {$done < $frame_words} {
            set address [expr {$base+$done*4}]
            # AXI INCR bursts must not cross a 4 KiB boundary.
            set n [expr {min($burst_words, $frame_words-$done, (4096-($address%4096))/4)}]
            foreach word [read_burst $hw_axi $address $n] {puts $handle $word}
            incr done $n
            if {[incr bursts]%200 == 0 || $done == $frame_words} {
                puts [format {buff_%d: %d/%d words (%.0f%%)} $id $done $frame_words [expr {100.0*$done/$frame_words}]]
            }
        }
    } reason options]
    close $handle
    if {$failed} {
        puts stderr "Incomplete dump retained: $partial"
        return -options $options $reason
    }
    file rename -force -- $partial $filename
}

proc ::capture_frame::main {} {
    variable buffers
    set axis [get_hw_axis]
    if {[llength $axis] != 1} {
        error "Expected exactly one JTAG to AXI core, found: $axis"
    }
    set hw_axi [lindex $axis 0]
    puts "JTAG AXI: $hw_axi"
    puts {LIVE DUMP: the writer is not paused; an image may mix several frames.}
    foreach {id base} $buffers {
        dump $hw_axi $id [expr {$base+0}]
    }
    puts "DONE: open ov7670_capture.ipynb and Run All."
}

::capture_frame::main
