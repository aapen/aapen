"""
Copyright (c) 2019 Ash Wilding. All rights reserved.
          (c) 2021 42Bastian Schick

SPDX-License-Identifier: MIT
"""

# Internal deps
from . import args
from . import log
from . import mmu
from . import table
from . import mmap
from .mmap import Region

def _mk_table( n:int, t:table.Table ) -> str:
    """
    Generate assembly to begin programming a translation table.

    args
    ====

        n
                    table number in sequential order from ttbr0_eln

        t
                    translation table being programmed
    """
    return f"""
/* program_table_{n} */
    MOV64   x21, {hex(t.addr)}          // base address of this table
    add     x21, x21, x20       // add global base
    MOV64   x22, {hex(t.chunk)}         // chunk size"""

def _mk_blocks( n:int, t:table.Table, index:int, r:Region ) -> str:
    """
    Generate assembly to program a range of contiguous block/page entries.

    args
    ====

        n
                    table number in sequential order from ttbr0_eln

        t
                    translation table being programmed

        index
                    index of the first block/page in the contiguous range

        r
                    the memory region
    """
    (value,comment) = mmu.block_page_template(r.memory_type, r.ap_type, t.level >= 3)
    if r.num_contig > 1:
        return f"""
/* {r.comment} */
/* {comment} */
    MOV64    x9, {value}  //
    MOV64   x10, {index}            // index: {index}
    MOV64   x11, {index + r.num_contig}     // to {index + r.num_contig} ({r.num_contig} entries)
    MOV64   x12, {hex(r.addr)}      // output address of entry[index]
pt{hex(r.addr)}:
    orr     x12, x12, x9    // merge output address with template
    str     X12, [x21, x10, lsl #3]     // write entry into table
    add     x10, x10, #1                // prepare for next entry
    add     x12, x12, x22               // add chunk to address
    cmp     x10, x11            // last index?
    b.ne    pt{hex(r.addr)}                     //
"""
    else:
        return f"""
/* {r.comment} */
/* {comment} */
    MOV64    x9, {value} //
    MOV64   x10, {index}                // index: {index}
    MOV64   x12, {hex(r.addr)}      // output address of entry[index]
    orr     x12, x12, x9    // merge output address with template
    str     x12, [x21, x10, lsl #3]     // write entry into table
"""



def _mk_next_level_table( n:int, index:int, next_t:table.Table ) -> str:
    """
    args
    ====

        n
                    parent table number in sequential order from ttbr0_eln

        index
                    index of the next level table pointer

        next_t
                    the next level translation table
    """
#/* program_table_{n}_entry_{index} */
    return f"""
    MOV64   x11, {hex(next_t.addr)} // next-level table address
    add     x11, x11, x20               // add base address
    orr     x11, x11, #0x3              // next-level table descriptor
    str     x11, [x21, #{index}*8]     // write entry[{index}] into table"""


def _mk_asm() -> str:
    """
    Generate assembly to program all allocated translation tables.
    """
    string = ""
    for n,t in enumerate(table.Table._allocated):
        string += _mk_table(n, t)
        keys = sorted(list(t.entries.keys()))
        while keys:
            index = keys[0]
            entry = t.entries[index]
            if type(entry) is Region:
                string += _mk_blocks(n, t, index, entry)
                for k in range(index, index+entry.num_contig):
                    keys.remove(k)
            else:
                string += _mk_next_level_table(n, index, entry)
                keys.remove(index)
    return string

ttbr="ttbr0"
ttbro="ttbr1"
if args.ttbr1:
   ttbr="ttbr1"
   ttbro="ttbr0"

_newline = "\n"
_tmp =f"""/*
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
{_newline.join([f' * {ln}' for ln in str(table.root).splitlines()])}
 *
 * The following command line arguments were passed to arm64-pgtable-tool:
 *
 *      -i {args.i}
 *      -ttb {args.ttb}
 *      -el {args.el}
 *      -tg {args.tg_str}
 *      -tsz {args.tsz}
 *{f'      -no_mmuon' if args.no_mmuon else ''}
 *{f'      -l {args.label[1:]}' if args.label != "" else ''}
 *
{_newline.join([f' * {ln}' for ln in table.Table.usage().splitlines()])}
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

     /* some handy macros */
#ifdef __IAR_SYSTEMS_ASM__
FUNC64 MACRO
    SECTION .text_\\1:CODE:NOROOT(3)
    EXPORT  \\1
\\1
    ENDM

ENDFUNC MACRO
    ALIGNROM 3
    LTORG
\\1_size:    EQU . - \\1
    ENDM

  MOV64:    MACRO   reg,value
    if (value & 0xffff) || (value == 0)
    movz    reg,#value & 0xffff
    endif
    if value > 0xffff && ((value>>16) & 0xffff) != 0
    if (value & 0xffff)
    movk    reg,#(value>>16) & 0xffff,lsl #16
    else
    movz    reg,#(value>>16) & 0xffff,lsl #16
    endif
    endif
    if value > 0xffffffff && ((value>>32) & 0xffff) != 0
    if value & 0xffffffff
    movk    reg,#(value>>32) & 0xffff,lsl #32
    else
    movz    reg,#(value>>32) & 0xffff,lsl #32
    endif
    endif
    if value > 0xffffffffffff && ((value>>48) & 0xffff) != 0
    if value & 0xffffffffffff
    movk    reg,#(value>>48) & 0xffff,lsl #48
    else
    movz    reg,#(value>>48) & 0xffff,lsl #48
    endif
    endif
    ENDM
#else
#define END .end
    .macro  FUNC64 name
    .section .text.\\name,"ax"
    .type   \\name,%function
    .globl  \\name
\\name:
    .endm

    .macro  ENDFUNC name
    .align  3
    .pool
    .globl  \\name\\()_end
\\name\\()_end:
    .size   \\name,.-\\name
    .endm

    .macro  MOV64 reg,value
    .if \\value & 0xffff || (\\value == 0)
    movz    \\reg,#\\value & 0xffff
    .endif
    .if \\value > 0xffff && ((\\value>>16) & 0xffff) != 0
    .if \\value & 0xffff
    movk    \\reg,#(\\value>>16) & 0xffff,lsl #16
    .else
    movz    \\reg,#(\\value>>16) & 0xffff,lsl #16
    .endif
    .endif
    .if \\value > 0xffffffff && ((\\value>>32) & 0xffff) != 0
    .if \\value & 0xffffffff
    movk    \\reg,#(\\value>>32) & 0xffff,lsl #32
    .else
    movz    \\reg,#(\\value>>32) & 0xffff,lsl #32
    .endif
    .endif
    .if \\value > 0xffffffffffff && ((\\value>>48) & 0xffff) != 0
    .if \\value & 0xffffffffffff
    movk    \\reg,#(\\value>>48) & 0xffff,lsl #48
    .else
    movz    \\reg,#(\\value>>48) & 0xffff,lsl #48
    .endif
    .endif
    .endm
#endif
/**
 * Setup the page table.
 * Not reentrant!
 */
    FUNC64 pagetable_init{args.label} //
    adrp    x20, {args.ttb} // base address
/* zero_out_tables */
    mov     x2,x20 //
    MOV64   x3, {hex(args.tg * len(table.Table._allocated))}// combined length of all tables
ptclear{args.label}:
    stp     xzr, xzr, [x2]       // zero out 2 table entries at a time
    subs    x3, x3, #16     //
    add     x2, x2, #16     //
    b.ne    ptclear{args.label}            //
{_mk_asm()}
    ret                             // done!
    ENDFUNC pagetable_init{args.label}  //

#ifdef __IAR_SYSTEMS_ASM__
    SECTION noinit_mmu:DATA
    EXPORT {args.ttb}
    ALIGNRAM 12
{args.ttb}: DS8 {hex(args.tg * len(table.Table._allocated))}
#else
    .section .noinit.mmu,"aw",@nobits
    .globl {args.ttb}
    .align 12
{args.ttb}: .space {hex(args.tg * len(table.Table._allocated))}
#endif
"""

mmu_on = f"""
/*
 * Set translation table and enable MMU
 */
    FUNC64 mmu_on //
    adrp    x1, mmu_init            // get 4KB page containing mmu_init
    ldr     w2, [x1,#:lo12:mmu_init]    // read mmu_init
    cbz     w2, .                   // init not done, endless loop

    adrp    x6, {args.ttb}      // address of first table
    msr     {ttbr}_el{args.el}, x6  //
    .if {args.el} == 1          //
    msr     {ttbro}_el1,xzr         //
    .endif                      //
    /**********************************************
    * Set up memory attributes
    * This equates to:
    * 0 = b00000000 = Device-nGnRnE
    * 1 = b11111111 = Normal, Inner/Outer WB/WA/RA
    * 2 = b01000100 = Normal, Inner/Outer Non-Cacheable
    * 3 = b10111011 = Normal, Inner/Outer WT/WA/RA
    **********************************************/

    msr MAIR_EL1, x1                //
    MOV64   x1, {mmu.mair}          // program mair on this CPU
    msr     mair_el{args.el}, x1 //
    MOV64   x1, {mmu.tcr}           // program tcr on this CPU
    msr     tcr_el{args.el}, x1 //
    isb //
    mrs     x2, tcr_el{args.el}         // verify CPU supports desired config
    cmp     x2, x1 //
    b.ne    .                       //
    MOV64   x1, {mmu.sctlr}         // program sctlr on this CPU
    msr     sctlr_el{args.el}, x1       //
    isb                             // synchronize context on this CPU
    ret                             //
    ENDFUNC mmu_on
"""
TAB='\t'
output = ""
for line in _tmp.splitlines():
    if "//" in line and not " *" in line:
        index = line.index("//")
        code = line[:index].rstrip(" \t").lstrip(" \t")
        comment = line[index:]
        line = f"\t{code}{TAB * (4-(len(code)>>3))}{comment}"
    elif not " *" and not "/*" and not "*/" in line:
        line = f"\t"+line.rstrip().lstrip()
    output += f"{line}\n"

if not args.no_mmuon:
    for line in mmu_on.splitlines():
        if "//" in line and not " *" in line:
            index = line.index("//")
            code = line[:index].rstrip(" \t").lstrip(" \t")
            comment = line[index:]
            line = f"\t{code}{TAB * (4-(len(code)>>3))}{comment}"
        elif not " *" and not "/*" and not "*/" in line:
            line = f"\t"+line.rstrip().lstrip()
        output += f"{line}\n"
output += f"\tEND\n"
[log.verbose(line) for line in output.splitlines()]
