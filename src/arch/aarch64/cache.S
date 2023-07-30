#include <asm/macro.h>


// ----------------------------------------------------------------------
// fn flushDCacheRange(start, end)
//
// clean and invalidate data cache for all addresses in the range (note this
// function only differs from invalidateDCacheRange by the argument to the
// `dc` instruction.)
//
// Arguments:
//      x0 - start address
//      x1 - end address
// Returns: none
// ----------------------------------------------------------------------
        ENTRY(flushDCacheRange)

        mrs x3, ctr_el0         // get the cache type register (CTR)
        ubfx x3, x3, #16, #4    // extract the DminLine field from CTR
        mov x2, #4              // DminLine is log2 the # of words
        lsl x2, x2, x3          // x2 <- 4 << DminLine (# of bytes)
        // x2 now hold the minimal data cache line size in the system

        sub x3, x2, #1          // x3 <- cache line size - 1
        bic x0, x0, x3          // clear the bottom bits of the start
                                // address (aligns it down to previous
                                // multiple of the cache line size)
1:      dc civac, x0            // civac = clean & invalidate by
                                // virtual address to point of
                                // consistency
        add x0, x0, x2          // go to next cache-line-aligned
                                // address
        cmp x0, x1              // if we've not reached the end
        b.lo 1b                 // loop
        dsb sy                  // else force pending writes to
                                // complete
        ret                     // and exit
        END(flushDcacheRange)

// ----------------------------------------------------------------------
// fn invalidateDCacheRange(start, end)
//
// invalidate data cache for all addresses in the range (note this
// function only differs from flushDCacheRange by the argument to the
// `dc` instruction.)
//
// Arguments:
//      x0 - start address
//      x1 - end address
// Returns: none
// ----------------------------------------------------------------------

        ENTRY(invalidateDCacheRange)
        mrs x3, ctr_el0         // get the cache type register (CTR)
        ubfx x3, x3, #16, #4    // extract the DminLine field from CTR
        mov x2, #4              // DminLine is log2 the # of words
        lsl x2, x2, x3          // x2 <- 4 << DminLine (# of bytes)
        // x2 now hold the minimal data cache line size in the system

        sub x3, x2, #1          // x3 <- cache line size - 1
        bic x0, x0, x3          // clear the bottom bits of the start
                                // address (aligns it down to previous
                                // multiple of the cache line size)
1:      dc ivac, x0             // ivac = invalidate by virtual address
                                // to point of consistency
        add x0, x0, x2          // go to next cache-line-aligned
                                // address
        cmp x0, x1              // if we've not reached the end
        b.lo 1b                 // loop
        dsb sy                  // else force pending writes to
                                // complete
        ret                     // and exit

        END(invalidateDCacheRange)
