# arm64-pgtable-tool

This tool has a lineage:

- Originally [ashwio/arm64-pgtable-tool](https://github.com/ashwio/arm64-pgtable-tool)
- Forked as [42Bastian/arm64-pgtable-tool](https://github.com/42Bastian/arm64-pgtable-tool) with some additional options.
- Vendored into [mtnygard/pijFORTHos](https://github.com/mtnygard/pijFORTHos) to adapt the code generation.

## Introduction

Tool for automatically generating MMU and translation table setup code, whether to drag and drop into your own bare metal arm64 projects or to assist you in your own learning.

For more information see [the original blog post](https://ashw.io/blog/arm64-pgtable-tool).

## Prerequisites

* Python 3.8+
* [chaimleib's IntervalTree](https://github.com/chaimleib/intervaltree)

```
    pip install intervaltree
```

## Usage

The following command-line options are available:

```
  -h, --help            show this help message and exit
  -i SRC                input memory map file
  -no_mmuon             Do not generate mmu_on function
  -o DST                output GNU assembly file (default mmu_setup.S)
  -ttbr1                Use TTBR1 instead of TTBR0 (default)
  -ttb TTB              desired translation table base address as symbol! (default
                        mmu_table)
  -el {1,2,3}           exception level (default: 1)
  -tg {4K,16K,64K,4k,16k,64k}
                        translation granule (default: 4K)
  -tsz {32,36,40,48}    address space size (default: 40)
  -l label              extend labels with a custom identifier
  -v                    verbose
  -d                    enable debug output
```

### Input memory map file

The input memory map file is a simple comma-separated text file with format:

```
  phyAddress,[virtAddress], size, type[:SHARED][:GLOBAL], rights[:SX][:UX][:NS], comment
```

Empty lines are allowed. Line comments may start with `#` or `//`.

Where:

* `phyAddress` is the physical address of a region;
* `virtAddress` is the virtual address of a region, if empty `phyAddress` is used;
* `size` is the size of the region  in bytes, using `K`, `M`, or `G` to specify the unit;
* `type` can be `DEVICE`, `NO_CACHE`, `CACHE_WB?` or `CACHE_WT`. `:SHARED` sets the shared and `:GLOBAL` the global flag;
* `rights` are the access rights (`AP[2..1]`). There are four combinations: `SRW_UNA`, `SRW_URW`, `SRO_UNA` and `SRO_URO`. By default a region is "XN" with `:SX` or `:UX` execution rights can be set. With `:NS` the non-secure flag will be set.
* `comment` This is a comment added in the output easy tracing.

The address parameter can be a valid python expression.

Memory types are:

* `DEVICE`:   Device (no caching, guarded)
* `CACHE_WB`: Writeback cache
* `CACHE_WT`: Writethru cache
* `NO_CACHE`: Not cached

The rights are:

* `SRW_UNA` : Supervisor Read/Write, User No Access
* `SRW_URW` : Supervisor Read/Write, User Read/Write
* `SRO_UNA` : Supervisor Read Only, User No Access
* `SRO_URO` : Supervisor Read Only, User Read Only

_Note_: A writable region is automatically `SXN`.

Several memory map files are provided in the [examples folder](examples).

### Translation table base address

This must be the base address of a granule aligned buffer that is at least large enough to contain the number of translation tables allocated by the tool.

You can see this in the generated GNU assembly file:

```
    /*
     * ...
     *
     * This memory map requires a total of 7 translation tables.
     * Each table occupies 4K of memory (0x1000 bytes).
     * The buffer pointed to by "mmu_table" is therefore 7x 4K = 0x7000 bytes long.
     *
     * ...
     */
```

It is also your responsibility to ensure the memory region containing the buffer is described as `NORMAL` in the input memory map file.

### Exception level

The tool only programs `TTBR0_ELn` at the specified exception level. Where two virtual address spaces are available, such as at EL1, the higher virtual address space pointed to by `TTBR1_ELn` is disabled.

If **EL1** is chosen, the other `TTBRx` is cleared.

### Translation table

By default `TTBR0` is used. With the option `-ttbr1`, one can use `TTBR1`, but only in **EL1**.

### Translation granule

The `4K` and `64K` granules have been tested on an i.MX8MQ. Unfortunately the `16K` granule is not supported by this chip so has not been tested.


## Example output

Running the following command:

```
    python3.8 generate.py -i examples/base-fvp-minimal.txt -no_mmuon
```

Where `examples/base-fvp-minimal.txt` contains:

```
# Comment
// another comment
0x01C090000,,   4K, DEVICE,   SRW_UNA, UART0
0x02C000000,,   8K, DEVICE,   SRW_UNA, GICC
0x02E000000,,  64K, CACHE_WB, SRW_UNA, Non-Trusted SRAM
0x02F000000,,  64K, DEVICE,   SRW_UNA, GICv3 GICD
0x02F000000+0x100000,,   1M, DEVICE,   SRW_UNA, GICv3 GICR
0x080000000,,   1G, CACHE_WT, SRW_UNA, Non-Trusted DRAM

0x0C0000000,,   2M, CACHE_WB, SRO_UNA:SX, CODE
```

Generates the following `mmu_setup.S` GNU assembly file:

```
/*
 * This file was automatically generated using arm64-pgtable-tool.
 * See: https://github.com/42Bastian/arm64-pgtable-tool
 * Forked from: https://github.com/ashwio/arm64-pgtable-tool
 *
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * This code programs the following translation table structure:
 *
 * Index     physical             =>  virtual              Type
 * -----------------------------------------------------------------------------
 *                                                         SNC P  U  P  U  S G
 *                                               shared ___| | r  s  r  s  e l
 *                                            no cache  NC___| i  e  i  e  c o
 *                                              device  DE___| n  r  v  r  u b
 *                                          write back  WB___|             r a
 *                                          write thru  WT___| Exe   AP    e L
 * -----------------------------------------------------------------------------
 * level 0 table @ mmu_table + 0x0
 * [   0]-----------------------------\
 *  level 1 table @ mmu_table + 0x1000
 *  [   0]-----------------------------\
 *   level 2 table @ mmu_table + 0x2000
 *   [ 224]-----------------------------\
 *    level 3 table @ mmu_table + 0x3000
 *            --- UART0 ---
 *    [ 144] 001c090000-001c090fff=>001c090000-001c090fff,  DE XN XN WR UN S -
 *   [ 352]-----------------------------\
 *    level 3 table @ mmu_table + 0x4000
 *            --- GICC ---
 *    [   0] 002c000000-002c000fff=>002c000000-002c000fff,  DE XN XN WR UN S -
 *    [   1] 002c001000-002c001fff=>002c001000-002c001fff,  DE XN XN WR UN S -
 *   [ 368]-----------------------------\
 *    level 3 table @ mmu_table + 0x5000
 *            --- Non-Trusted SRAM ---
 *    [   0] 002e000000-002e000fff=>002e000000-002e000fff,  WB XN XN WR UN S -
 *            ...
 *    [  15] 002e00f000-002e00ffff=>002e00f000-002e00ffff,  WB XN XN WR UN S -
 *   [ 376]-----------------------------\
 *    level 3 table @ mmu_table + 0x6000
 *            --- GICv3 GICD ---
 *    [   0] 002f000000-002f000fff=>002f000000-002f000fff,  DE XN XN WR UN S -
 *            ...
 *    [  15] 002f00f000-002f00ffff=>002f00f000-002f00ffff,  DE XN XN WR UN S -
 *            --- GICv3 GICR ---
 *    [ 256] 002f100000-002f100fff=>002f100000-002f100fff,  DE XN XN WR UN S -
 *            ...
 *    [ 511] 002f1ff000-002f1fffff=>002f1ff000-002f1fffff,  DE XN XN WR UN S -
 *            --- Non-Trusted DRAM ---
 *  [   2]   0080000000-00bfffffff=>0080000000-00bfffffff,  WT XN XN WR UN S -
 *  [   3]-----------------------------\
 *   level 2 table @ mmu_table + 0x7000
 *            --- CODE ---
 *   [   0]  00c0000000-00c01fffff=>00c0000000-00c01fffff,  WB  X XN RO UN S -
 *
 * The following command line arguments were passed to arm64-pgtable-tool:
 *
 *      -i examples/base-fvp-minimal.txt
 *      -ttb mmu_table
 *      -el 1
 *      -tg 4K
 *      -tsz 40
 *      -no_mmuon
 *
 *
 * This memory map requires a total of 8 translation tables.
 * Each table occupies 4K of memory (0x1000 bytes).
 * The buffer pointed to by 'mmu_table' is therefore 8x4K = 0x8000 bytes long.
 *
 * The programmer must also ensure that the virtual memory region containing the
 * translation tables is itself marked as NORMAL in the memory map file.
 * MAIR should be set like this:
 *
 * 0 = b00000000 = Device-nGnRnE
 * 1 = b11111111 = Normal, Inner/Outer WB/WA/RA
 * 2 = b01000100 = Normal, Inner/Outer Non-Cacheable
 * 3 = b10111011 = Normal, Inner/Outer WT/WA/RA
 *
 * For example
 *
 *  MOV64   x1, 0xbb44ff00               // program mair on this CPU
 *  msr     mair_el1, x1
 */

.macro  FUNC64 name
    .section .text.\name
    .type    \name, @function
    .global  \name
\name:
.endm

.macro  ENDFUNC name
    .align  3
    .pool
    .global \name\()_end
\name\()_end:
    .size   \name,.-\name
.endm

.macro  MOV64 reg,value
    .if \value & 0xffff || (\value == 0)
    movz    \reg,#\value & 0xffff
    .endif
    .if \value > 0xffff && ((\value>>16) & 0xffff) != 0
    .if \value & 0xffff
    movk    \reg,#(\value>>16) & 0xffff,lsl #16
    .else
    movz    \reg,#(\value>>16) & 0xffff,lsl #16
    .endif
    .endif
    .if \value > 0xffffffff && ((\value>>32) & 0xffff) != 0
    .if \value & 0xffffffff
    movk    \reg,#(\value>>32) & 0xffff,lsl #32
    .else
    movz    \reg,#(\value>>32) & 0xffff,lsl #32
    .endif
    .endif
    .if \value > 0xffffffffffff && ((\value>>48) & 0xffff) != 0
    .if \value & 0xffffffffffff
    movk    \reg,#(\value>>48) & 0xffff,lsl #48
    .else
    movz    \reg,#(\value>>48) & 0xffff,lsl #48
    .endif
    .endif
.endm

/**
 * Setup the page table.
 * Not reentrant!
 */
	FUNC64 pagetable_init		//

					// Save x19, x20, x21, x22
    sub     sp, sp, #16 * 2
    stp     x19, x20, [sp, #16 * 0]
    stp     x21, x22, [sp, #16 * 1]

	adrp    x20, mmu_table		// base address
/* zero_out_tables */
	mov     x2,x20			//
	MOV64   x3, 0x8000		// combined length of all tables
ptclear:
	stp     xzr, xzr, [x2]		// zero out 2 table entries at a time
	subs    x3, x3, #16		//
	add     x2, x2, #16		//
	b.ne    ptclear			//

/* program_table_0 */
	MOV64   x21, 0x0		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x8000000000	// chunk size
	MOV64   x11, 0x1000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #0*8]	// write entry[0] into table
/* program_table_1 */
	MOV64   x21, 0x1000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x40000000		// chunk size
	MOV64   x11, 0x2000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #0*8]	// write entry[0] into table
/* Non-Trusted DRAM */
/* page:0x0 SH:0x0 AF:0x1 nG:0x1 attrindx:0x3 NS:0x0 xn:0x1 pxn:0x1 AP:0x0  */
	MOV64    x9, 0x60000000000c0d	//
	MOV64   x10, 2			// index: 2
	MOV64   x12, 0x80000000		// output address of entry[index]
	orr     x12, x12, x9		// merge output address with template
	str     x12, [x21, x10, lsl #3]	// write entry into table

	MOV64   x11, 0x7000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #3*8]	// write entry[3] into table
/* program_table_2 */
	MOV64   x21, 0x2000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x200000		// chunk size
	MOV64   x11, 0x3000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #224*8]	// write entry[224] into table
	MOV64   x11, 0x4000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #352*8]	// write entry[352] into table
	MOV64   x11, 0x5000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #368*8]	// write entry[368] into table
	MOV64   x11, 0x6000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #376*8]	// write entry[376] into table
/* program_table_3 */
	MOV64   x21, 0x3000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x1000		// chunk size
/* UART0 */
/* page:0x1 SH:0x0 AF:0x1 nG:0x1 attrindx:0x0 NS:0x0 xn:0x1 pxn:0x1 AP:0x0  */
	MOV64    x9, 0x60000000000c03	//
	MOV64   x10, 144		// index: 144
	MOV64   x12, 0x1c090000		// output address of entry[index]
	orr     x12, x12, x9		// merge output address with template
	str     x12, [x21, x10, lsl #3]	// write entry into table

/* program_table_4 */
	MOV64   x21, 0x4000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x1000		// chunk size
/* GICC */
/* page:0x1 SH:0x0 AF:0x1 nG:0x1 attrindx:0x0 NS:0x0 xn:0x1 pxn:0x1 AP:0x0  */
	MOV64    x9, 0x60000000000c03	//
	MOV64   x10, 0			// index: 0
	MOV64   x11, 2			// to 2 (2 entries)
	MOV64   x12, 0x2c000000		// output address of entry[index]
pt0x2c000000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x2c000000		//

/* program_table_5 */
	MOV64   x21, 0x5000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x1000		// chunk size
/* Non-Trusted SRAM */
/* page:0x1 SH:0x0 AF:0x1 nG:0x1 attrindx:0x1 NS:0x0 xn:0x1 pxn:0x1 AP:0x0  */
	MOV64    x9, 0x60000000000c07	//
	MOV64   x10, 0			// index: 0
	MOV64   x11, 16			// to 16 (16 entries)
	MOV64   x12, 0x2e000000		// output address of entry[index]
pt0x2e000000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x2e000000		//

/* program_table_6 */
	MOV64   x21, 0x6000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x1000		// chunk size
/* GICv3 GICD */
/* page:0x1 SH:0x0 AF:0x1 nG:0x1 attrindx:0x0 NS:0x0 xn:0x1 pxn:0x1 AP:0x0  */
	MOV64    x9, 0x60000000000c03	//
	MOV64   x10, 0			// index: 0
	MOV64   x11, 16			// to 16 (16 entries)
	MOV64   x12, 0x2f000000		// output address of entry[index]
pt0x2f000000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x2f000000		//

/* GICv3 GICR */
/* page:0x1 SH:0x0 AF:0x1 nG:0x1 attrindx:0x0 NS:0x0 xn:0x1 pxn:0x1 AP:0x0  */
	MOV64    x9, 0x60000000000c03	//
	MOV64   x10, 256		// index: 256
	MOV64   x11, 512		// to 512 (256 entries)
	MOV64   x12, 0x2f100000		// output address of entry[index]
pt0x2f100000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x2f100000		//

/* program_table_7 */
	MOV64   x21, 0x7000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x200000		// chunk size
/* CODE */
/* page:0x0 SH:0x0 AF:0x1 nG:0x1 attrindx:0x1 NS:0x0 xn:0x1 pxn:0x0 AP:0x2  */
	MOV64    x9, 0x40000000000c85	//
	MOV64   x10, 0			// index: 0
	MOV64   x12, 0xc0000000		// output address of entry[index]
	orr     x12, x12, x9		// merge output address with template
	str     x12, [x21, x10, lsl #3]	// write entry into table


					// Restore x19, x20, x21, x22
    ldp x19, x20, [sp, #16 * 0]
    ldp x21, x22, [sp, #16 * 1]
    add sp, sp, #16 * 2

	ret				// done!
	ENDFUNC pagetable_init		//

    .section .noinit.mmu,"aw",@nobits
    .global mmu_table
    .align 12
mmu_table: .space 0x8000
```
