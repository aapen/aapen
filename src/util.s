        .section .text.util
        
// ----------------------------------------------------------------------
// fn spin_delay()
//
// Arguments:
//      x0 - number of cycles to spin for
// Returns: none
// Clobbers: x0
// ----------------------------------------------------------------------
        .global spin_delay
        .type spin_delay, @function
spin_delay:
    subs x0, x0, #1
    bne spin_delay
    ret