/*
 * This file was automatically generated using arm64-pgtable-tool.
 * See: https://github.com/42Bastian Schick/arm64-pgtable-tool
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
 * level 0 table @ __page_tables_start + 0x0
 * [   0]---------------------------------------\
 *  level 1 table @ __page_tables_start + 0x1000
 *  [   0]---------------------------------------\
 *   level 2 table @ __page_tables_start + 0x2000
 *   [   0]---------------------------------------\
 *    level 3 table @ __page_tables_start + 0x3000
 *            --- Kernel stack ---
 *    [   0] 0000000000-0000000fff=>0000000000-0000000fff, SWB XN XN RW RW S -
 *            ...
 *    [ 127] 000007f000-000007ffff=>000007f000-000007ffff, SWB XN XN RW RW S -
 *            --- Kernel code ---
 *    [ 128] 0000080000-0000080fff=>0000080000-0000080fff, SWB  X  X RO RO S -
 *            ...
 *    [ 255] 00000ff000-00000fffff=>00000ff000-00000fffff, SWB  X  X RO RO S -
 *            --- Kernel data ---
 *    [ 256] 0000100000-0000100fff=>0000100000-0000100fff, SWB XN XN RW RW S -
 *            ...
 *    [ 511] 00001ff000-00001fffff=>00001ff000-00001fffff, SWB XN XN RW RW S -
 *            --- Kernel data ---
 *   [   1]  0000200000-00003fffff=>0000200000-00003fffff, SWB XN XN RW RW S -
 *           ...
 *   [ 255]  001fe00000-001fffffff=>001fe00000-001fffffff, SWB XN XN RW RW S -
 *   [ 256]---------------------------------------\
 *    level 3 table @ __page_tables_start + 0x4000
 *            --- Kernel data ---
 *    [   0] 0020000000-0020000fff=>0020000000-0020000fff, SWB XN XN RW RW S -
 *            ...
 *    [ 255] 00200ff000-00200fffff=>00200ff000-00200fffff, SWB XN XN RW RW S -
 *            --- MMIO block ---
 *   [ 504]  003f000000-003f1fffff=>003f000000-003f1fffff, SDE XN XN RW RW S -
 *           ...
 *   [ 511]  003fe00000-003fffffff=>003fe00000-003fffffff, SDE XN XN RW RW S -
 *
 * The following command line arguments were passed to arm64-pgtable-tool:
 *
 *      -i ../pgtable-input-pi3.txt
 *      -ttb __page_tables_start
 *      -el 1
 *      -tg 4K
 *      -tsz 40
 *
 *
 *
 * This memory map requires a total of 5 translation tables.
 * Each table occupies 4K of memory (0x1000 bytes).
 * The buffer pointed to by '__page_tables_start' is therefore 5x4K = 0x5000 bytes long.
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

	adrp    x20, __page_tables_start// base address
/* zero_out_tables */
	mov     x2,x20			//
	MOV64   x3, 0x5000		// combined length of all tables
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
/* program_table_2 */
	MOV64   x21, 0x2000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x200000		// chunk size
	MOV64   x11, 0x3000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #0*8]	// write entry[0] into table
/* Kernel data */
/* page:0x0 SH:0x3 AF:0x1 nG:0x1 attrindx:0x1 NS:0x0 xn:0x1 pxn:0x1 AP:0x1  */
	MOV64    x9, 0x60000000000f45	//
	MOV64   x10, 1			// index: 1
	MOV64   x11, 256		// to 256 (255 entries)
	MOV64   x12, 0x200000		// output address of entry[index]
pt0x200000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x200000		//

	MOV64   x11, 0x4000		// next-level table address
	add     x11, x11, x20		// add base address
	orr     x11, x11, #0x3		// next-level table descriptor
	str     x11, [x21, #256*8]	// write entry[256] into table
/* MMIO block */
/* page:0x0 SH:0x3 AF:0x1 nG:0x1 attrindx:0x0 NS:0x0 xn:0x1 pxn:0x1 AP:0x1  */
	MOV64    x9, 0x60000000000f41	//
	MOV64   x10, 504		// index: 504
	MOV64   x11, 512		// to 512 (8 entries)
	MOV64   x12, 0x3f000000		// output address of entry[index]
pt0x3f000000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x3f000000		//

/* program_table_3 */
	MOV64   x21, 0x3000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x1000		// chunk size
/* Kernel stack */
/* page:0x1 SH:0x3 AF:0x1 nG:0x1 attrindx:0x1 NS:0x0 xn:0x1 pxn:0x1 AP:0x1  */
	MOV64    x9, 0x60000000000f47	//
	MOV64   x10, 0			// index: 0
	MOV64   x11, 128		// to 128 (128 entries)
	MOV64   x12, 0x0		// output address of entry[index]
pt0x0:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x0			//

/* Kernel code */
/* page:0x1 SH:0x3 AF:0x1 nG:0x1 attrindx:0x1 NS:0x0 xn:0x0 pxn:0x0 AP:0x3  */
	MOV64    x9, 0xfc7		//
	MOV64   x10, 128		// index: 128
	MOV64   x11, 256		// to 256 (128 entries)
	MOV64   x12, 0x80000		// output address of entry[index]
pt0x80000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x80000		//

/* Kernel data */
/* page:0x1 SH:0x3 AF:0x1 nG:0x1 attrindx:0x1 NS:0x0 xn:0x1 pxn:0x1 AP:0x1  */
	MOV64    x9, 0x60000000000f47	//
	MOV64   x10, 256		// index: 256
	MOV64   x11, 512		// to 512 (256 entries)
	MOV64   x12, 0x100000		// output address of entry[index]
pt0x100000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x100000		//

/* program_table_4 */
	MOV64   x21, 0x4000		// base address of this table
	add     x21, x21, x20		// add global base
	MOV64   x22, 0x1000		// chunk size
/* Kernel data */
/* page:0x1 SH:0x3 AF:0x1 nG:0x1 attrindx:0x1 NS:0x0 xn:0x1 pxn:0x1 AP:0x1  */
	MOV64    x9, 0x60000000000f47	//
	MOV64   x10, 0			// index: 0
	MOV64   x11, 256		// to 256 (256 entries)
	MOV64   x12, 0x20000000		// output address of entry[index]
pt0x20000000:
	orr     x12, x12, x9		// merge output address with template
	str     X12, [x21, x10, lsl #3]	// write entry into table
	add     x10, x10, #1		// prepare for next entry
	add     x12, x12, x22		// add chunk to address
	cmp     x10, x11		// last index?
	b.ne    pt0x20000000		//


					// Restore x19, x20, x21, x22
    ldp x19, x20, [sp, #16 * 0]
    ldp x21, x22, [sp, #16 * 1]
    add sp, sp, #16 * 2

	ret				// done!
	ENDFUNC pagetable_init		//

    .section .noinit.mmu,"aw",@nobits
    .global __page_tables_start
    .align 12
__page_tables_start: .space 0x5000

/*
 * Set translation table and enable MMU
 */
	FUNC64 mmu_on			//

	adrp    x6, __page_tables_start	// address of first table
	msr     ttbr0_el1, x6		//
	.if 1 == 1			//
	msr     ttbr1_el1,xzr		//
	.endif				//
    /**********************************************
    * Set up memory attributes
    * This equates to:
    * 0 = b00000000 = Device-nGnRnE
    * 1 = b11111111 = Normal, Inner/Outer WB/WA/RA
    * 2 = b01000100 = Normal, Inner/Outer Non-Cacheable
    * 3 = b10111011 = Normal, Inner/Outer WT/WA/RA
    **********************************************/

	msr MAIR_EL1, x1		//
	MOV64   x1, 0xbb44ff00		// program mair on this CPU
	msr     mair_el1, x1		//
	MOV64   x1, 0x200803518		// program tcr on this CPU
	msr     tcr_el1, x1		//
	isb				//
	mrs     x2, tcr_el1		// verify CPU supports desired config
	cmp     x2, x1			//
	b.ne    .			//
	MOV64   x1, 0x1005		// program sctlr on this CPU
	msr     sctlr_el1, x1		//
	isb				// synchronize context on this CPU
	ret				//
    ENDFUNC mmu_on
