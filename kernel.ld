__rpi_physical_ram_start_addr   = 0;

/* Load address for kernel binary is defined by RPi's firmware */
__rpi_physical_binary_load_addr = 0x80000;

ENTRY(__rpi_physical_binary_load_addr)

/* Define program headers to load with correct protections. */
PHDRS
{
        segment_boot_core_stack PT_LOAD FLAGS(6);  /* RW */
        segment_code            PT_LOAD FLAGS(5);  /* RX */
        segment_data            PT_LOAD FLAGS(6);  /* RW */
}

SECTIONS
{
        . = __rpi_physical_ram_start_addr;

        /* Stack for the boot core tucks in from 0x00000 - 0x7ffff. */
        /* Stack grows downward (toward low memory) */
        .boot_core_stack (NOLOAD) :
        {
                . += __rpi_physical_binary_load_addr;
                __boot_core_stack_end_exclusive = .;
        } :segment_boot_core_stack

        .text :
        {
                KEEP(*(.text.boot))
                *(.text .text.*)
        } :segment_code

        .rodata : ALIGN(8)
        {
                *(.rodata*)
        } :segment_code

        .data :
        {
                *(.data*)
        } :segment_data

        .bss (NOLOAD) : ALIGN(16)
        {
                __bss_start = .;
                *(.bss*)
                __bss_end_exclusive = .;
        } :segment_data

        _end = .;

        /DISCARD/ :
        {
                *(.comment)
                *(.gnu.*)
                *(.note*)
                *(.eh_frame*)
        }
}

__bss_size = (__bss_end_exclusive - __bss_start) >> 3;
