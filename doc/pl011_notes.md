# State Machine and Interrupts

We want to use interrupt-driven IO to allow the device driver to
buffer outbound data then drain it out a byte at a time. (We currently
don't use the Tx or Rx FIFOs.) This means there is an interplay
between direct calls to the device driver and interrupt calls.

This state chart should help debug to make sure we get the sequencing right.

Current understanding:

-   After initialization and while it is idle, the UART's "raw interrupt status" (RIS) will not have any interrupt raised.
-   To get a transmit (TX) interrupt, we must first set the interrupt enable bit, then write an initial byte to the data register. Once that has finished sending, the UARTTXINTR will be raised.
-   This interrupt (as well as all other UART related interrupts) will be visible on the "masked interrupt status" (MIS) register if and only if the corresponding "interrupt mask set clear" (IMSC) bit has been set high.
    -   I.e., set bit 5 of IMSC to 1 to enable the TX interrupt.
    -   Then, when the TX interrupt occurs, it will signal to the interrupt controller (more about that later) <span class="underline">and</span> we will see bit 5 of the MIS register set high.
-   The "raw interrupt status" (RIS) register always reflects the interrupt bits, but an IRQ to the processor only happens when `RIS & IMSC` is not all zeroes.
-   The "interrupt clear register" (ICR) clears interrupts by setting the corresponding bit to high.
    -   I.e., set ICR bit 5 to 1 to clear the TX interrupt
-   However, the TX interrupt can also be cleared by writing one byte of data to the "data register" (DR)
-   The situation is analogous for a receive (RX) interrupt  with the following exceptions
    -   There is no need to "kick start" the RX interrupt. It happens as soon as the UART receives a byte.
    -   The RX interrupt is cleared by reading the DR.
    -   RX interrupts are on bit 4 of the various interrupt registers

# References

[PrimeCell UART (PL011) Technical Reference Manual](https://developer.arm.com/documentation/ddi0183/g/)
