"""
Copyright (c) 2019 Ash Wilding. All rights reserved.
          (c) 2021 42Bastian Schick

SPDX-License-Identifier: MIT
"""

# Standard Python deps
import math
from dataclasses import dataclass
from typing import List

# Internal deps
from . import args
from . import log
from .register import Register
from . import mmap


"""
Tables occupy one granule and each entry is a 64-bit descriptor.
"""
entries_per_table = args.tg // 8
log.debug(f"{entries_per_table=}")


"""
Number of bits required to index each byte in a granule sized page.
"""
block_offset_bits = int(math.log(args.tg, 2))
log.debug(f"{block_offset_bits=}")


"""
Number of bits required to index each entry in a complete table.
"""
table_idx_bits = int(math.log(entries_per_table, 2))
log.debug(f"{table_idx_bits=}")


"""
Starting level of translation.
"""
start_level = 3 - (args.tsz - block_offset_bits) // table_idx_bits
if (args.tsz - block_offset_bits) % table_idx_bits == 0:
    start_level = start_level + 1
    log.debug(f"start_level corrected as {args.tsz=} exactly fits in first table")
log.debug(f"{start_level=}")


def _tcr() -> str:
    """
    Generate required value for TCR_ELn.
    """
    reg = Register(f"tcr_el{args.el}")

    """
    Configurable bitfields present at all exception levels.
    """
    reg.field( 5,  0, "t0sz", 64-args.tsz)
    reg.field( 9,  8, "irgn0", 1)  # Normal WB RAWA
    reg.field(11, 10, "orgn0", 1)  # Normal WB RAWA
    reg.field(13, 12, "sh0", 3)    # Inner Shareable
    reg.field(15, 14, "tg0", {"4K":0, "16K":2, "64K":1}[args.tg_str])

    """
    Bits that are RES1 at all exception levels.
    """
    reg.res1(23) # technically epd1 at EL1 but we'll want =1 then anyway

    """
    Exception level specific differences.
    """
    ps_val = {32:0, 36:1, 40:2, 48:5}[args.tsz]
    if args.el == 1:
        reg.field(34, 32, "ps", ps_val)
    else:
        reg.field(18, 16, "ps", ps_val)
        reg.res1(31)

    return hex(reg.value()[0])

tcr = _tcr()

"""
AttrIndx [0] = Device-nGnRnE
AttrIndx [1] = Normal, Inner/Outer Write-Back RA/WA
AttrIndx [2] = Normal, Inner/Outer Non-Cacheable
AttrIndx [3] = Normal, Inner/Outer Write-Thru RA/WA
"""
mair = hex(0xBB44FF00)
log.debug(f"mair_el{args.el}={mair}")

ttbr = args.ttb
log.debug(f"ttbr0_el{args.el}={ttbr}")

if (args.ttbr1 != 0) & (args.el != 1):
   log.error(f"TTBR1 only in EL1")

def _sctlr() -> str:
    """
    Generate required value for SCTLR_ELn.
    """
    reg = Register(f"sctlr_el{args.el}")

    """
    Configurable bitfields present at all exception levels.
    """
    reg.field( 0,  0, "m", 1)    # MMU enabled
    reg.field( 2,  2, "c", 1)    # D-side access cacheability controlled by pgtables
    reg.field(12, 12, "i", 1),   # I-side access cacheability controlled by pgtables


    return hex(reg.value()[0])

sctlr = _sctlr()


def block_page_template ( memory_type:mmap.MEMORY_TYPE,
                          ap:mmap.AP_TYPE,
                          is_page:bool ):
    """
    Translation table entry fields common across all exception levels.
    """
    pte = Register("pte")
    pte.field( 0,  0, "-valid", 1)
    pte.field( 1,  1, "page", int(is_page))
    # Inner Shareable, ignored by Device memory
    pte.field( 9,  8, "SH", 3 if memory_type & 4 else 0)
    pte.field(10, 10, "AF", 1)  # Disable Access Flag faults
    pte.field(11, 11, "nG", 0 if memory_type & 8 else 1)
    mt = memory_type & 3
    if mt == mmap.MEMORY_TYPE.DEVICE:
        pte.field( 4,  2, "attrindx", 0)
    elif mt == mmap.MEMORY_TYPE.CACHE_WB:
        pte.field( 4,  2, "attrindx", 1)
    elif mt == mmap.MEMORY_TYPE.NO_CACHE:
        pte.field( 4,  2, "attrindx", 2)
    else:
        pte.field( 4,  2, "attrindx", 3)

    pte.field( 5, 5, "NS", int((ap & mmap.AP_TYPE.NS) != 0))
    """
    Exception level specific differences.
    """
    if (ap & mmap.AP_TYPE.UXN) and (ap & mmap.AP_TYPE.SXN):
        pte.field(54, 54, "xn", 1)
        pte.field(53, 53, "pxn", 1)
    elif (ap & mmap.AP_TYPE.UXN):
        pte.field(54, 54, "xn", 1)
        pte.field(53, 53, "pxn", 0)
    elif (ap & mmap.AP_TYPE.SXN):
        pte.field(54, 54, "xn", 0)
        pte.field(53, 53, "pxn", 1)
    else:
        pte.field(54, 54, "xn", 0)
        pte.field(53, 53, "pxn", 0)
    """
    Access rights
    """
    pte.field( 7,  6, "AP", ap & 3)

    return (hex(pte.value()[0]), pte.value()[1])

def table_template():
    return hex(0x3)
