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

// ----------------------------------------------------------------------
// fn global_disable_irq()
//
// Disable IRQs for the current PE
//
// Arguments: none
// Returns: none
// Clobbers: x0
// ----------------------------------------------------------------------
        .global global_disable_irq
        .type global_disable_irq, @function
global_disable_irq:
        msr daifset, #2
        ret

// ----------------------------------------------------------------------
// fn global_enable_irq()
//
// Enable IRQs for the current PE
//
// Arguments: none
// Returns: none
// Clobbers: x0
// ----------------------------------------------------------------------
        .global global_enable_irq
        .type global_enable_irq, @function
global_enable_irq:
        msr daifclr, #2
        ret