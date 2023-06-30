PAGE_SIZE = 4K;
PAGE_MASK = PAGE_SIZE-1;

/* The kernel's virtual address range will be:
 *
 * START:  max(u64) - __kernel_virt_addr_space_size + 1
 * END:    max(u64)
 */
__kernel_virt_addr_space_size = 1024 * 1024 * 1024;
__kernel_virt_start_addr = ((0xffffffffffffffff - __kernel_virt_addr_space_size) + 1);

__rpi_physical_ram_start_addr   = 0;

/* Load address for kernel binary is defined by RPi's firmware */
__rpi_physical_binary_load_addr = 0x80000;

ENTRY(__rpi_physical_binary_load_addr)

/* Define program headers to load with correct protections. */
PHDRS
{
        segment_code            PT_LOAD FLAGS(5);  /* RX */
        segment_data            PT_LOAD FLAGS(6);  /* RW */
        segment_heap            PT_LOAD FLAGS(6);  /* RW */
        segment_boot_core_stack PT_LOAD FLAGS(6);  /* RW */
}

SECTIONS
{
        . = __rpi_physical_ram_start_addr;

        /***********************************************************************
        * Boot core stack
        ***********************************************************************/
        .boot_core_stack (NOLOAD) :
        {
                __boot_core_stack_start = .;
                . += __rpi_physical_binary_load_addr;
                __boot_core_stack_end_exclusive = .;
        } :segment_boot_core_stack

        ASSERT((. & PAGE_MASK) == 0, "End of boot core stack is not page aligned")

        /***********************************************************************
        * Code
        ***********************************************************************/
        __code_start = .;
        .text : AT(__rpi_physical_binary_load_addr)
        {
                KEEP(*(.text._start))
                *(.text*)
        } :segment_code

        .got : { *(.got*) }

        .rodata : ALIGN(8)
        {
                *(.rodata*)
        } :segment_data

        . = ALIGN(512K);
        __code_end_exclusive = .;

        /***********************************************************************
        * Data + BSS
        ***********************************************************************/
        .page_tables(NOLOAD) : ALIGN(16)
        {
                __page_tables_start = .;
                . += 0x5000;
                __page_tables_end_exclusive = .;
        } :segment_data

        .bss (NOLOAD) : ALIGN(16)
        {
                __bss_start = .;
                *(.bss*);
                . = ALIGN(16);
                __bss_end_exclusive = .;
        } :segment_data

        __data_start = .;
        .data :
        {
                *(.data*)
        } :segment_data

        . = ALIGN(PAGE_SIZE);
        __data_end_exclusive = .;

        /***********************************************************************
        * Heap
        ***********************************************************************/
        __heap_start = .;
        .heap (NOLOAD) :
        {
                . += 512 * 1024 * 1024; /* 512MB heap */
        } :segment_heap
        __heap_end_exclusive = .;

        ASSERT((. & PAGE_MASK) == 0, "Heap is not page aligned")

        /***********************************************************************
        * Guard page
        ***********************************************************************/
        . += PAGE_SIZE;

        /***********************************************************************
        * Junk and gunk
        ***********************************************************************/

        /DISCARD/ :
        {
                *(.comment)
                *(.gnu.*)
                *(.note*)
                *(.eh_frame*)
        }
}
