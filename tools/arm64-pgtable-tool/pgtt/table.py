"""
Copyright (c) 2019 Ash Wilding. All rights reserved.
          (c) 2021 42Bastian Schick

SPDX-License-Identifier: MIT
"""

# Standard Python deps
from dataclasses import dataclass
from typing import List

# Internal deps
from . import args
from . import log
from . import mmu
from . import mmap


class Table:
    """
    Class representing a translation table.
    """
    _allocated = []


    def __init__( self, level:int=mmu.start_level, va_base:int=0 ):
        """
        Constructor.

        args
        ====

            level
                        level of translation

            va_base
                        base virtual address mapped by entry [0] in this table

        """
        self.addr = len(Table._allocated) * args.tg
        self.level = level
        self.chunk = args.tg << ((3 - self.level) * mmu.table_idx_bits)
        self.va_base = va_base
        self.entries = {}
        Table._allocated.append(self)


    def prepare_next( self, idx:int, va_base:int=None ) -> None:
        """
        Allocate next-level table at entry [idx] if it does not already point
        to a next-level table.

        Leave va_base=None to default to self.va_base + idx * self.chunk.
        """
        if not idx in self.entries:
            self.entries[idx] = Table(
                self.level + 1,
                va_base if not va_base is None else (self.va_base + idx * self.chunk)
            )


    def map( self, region:mmap.Region ) -> None:
        """
        Map a region of memory in this translation table.
        """
        log.debug()
        log.debug(f"mapping region {hex(region.virtaddr)}->{hex(region.addr)} in level {self.level} table {self.chunk}")
        log.debug(region)
        assert(region.virtaddr >= self.va_base)
        assert(region.virtaddr + region.length <= self.va_base + mmu.entries_per_table * self.chunk)

        """
        Calculate number of chunks required to map this region.
        A chunk is the area mapped by each individual entry in this table.
        start_idx is the first entry in this table mapping part of the region.
        """
        num_chunks = region.length // self.chunk
        start_idx = (region.virtaddr // self.chunk) % mmu.entries_per_table

        """
        Check whether the region is "floating".
        If so, dispatch to next-level table and we're finished.

                    +--------------------+
                 // |                    |
            Chunk - |####################| <-- Floating region
                 \\ |                    |
                    +--------------------+
        """
        if num_chunks == 0:
            log.debug(f"floating region, dispatching to next-level table at index {start_idx}")
            self.prepare_next(start_idx)
            self.entries[start_idx].map(region)
            return

        """
        Check for any "underflow".
        If so, dispatch the underflow to next-level table and proceed.

                    +--------------------+
                 // |####################|
            Chunk - |####################|
                 \\ |####################|
                    +--------------------+
                 // |####################| <-- Underflow
            Chunk - |                    |
                 \\ |                    |
                    +--------------------+
        """
        underflow = region.virtaddr % self.chunk
        if underflow:
            log.debug(f"{underflow=}, dispatching to next-level table at index {start_idx}")
            self.prepare_next(start_idx)
            self.entries[start_idx].map(region.copy(length=(self.chunk - underflow)))
            start_idx = start_idx + 1
            region.length -= self.chunk - underflow
            region.virtaddr += self.chunk - underflow
            region.addr += self.chunk - underflow
            log.debug(f"remaining: {region.length}")

        """
        Handle any remaining complete chunks.
        """

        blocks_allowed = self.level >= (1 if args.tg_str == "4K" else 2)
        num_contiguous_blocks = 0
        num_chunks = region.length // self.chunk
        for i in range(start_idx, start_idx + num_chunks):
            log.debug(f"mapping complete chunk at index {i} {hex(region.addr)}")
            r = region.copy(virtaddr=region.virtaddr, addr=region.addr, length=self.chunk)
            if not blocks_allowed:
                self.prepare_next(i)
                self.entries[i].map(r)
            else:
                self.entries[i] = r
            num_contiguous_blocks += 1
            region.addr += self.chunk
            region.virtaddr += self.chunk
            region.length -= self.chunk


        self.entries[start_idx].num_contig = num_contiguous_blocks
        start_idx += num_chunks;
        """
        Check for any "overflow".
        If so, dispatch the overflow to next-level table and proceed.

                    +--------------------+
                 // |                    |
            Chunk - |                    |
                 \\ |####################| <-- Overflow
                    +--------------------+
                 // |####################|
            Chunk - |####################|
                 \\ |####################|
                    +--------------------+
        """
        overflow = region.length
        if overflow:
            log.debug(f"{overflow=}, dispatching to next-level table at index {start_idx}")
            self.prepare_next(start_idx, region.virtaddr)
            self.entries[start_idx].map(region.copy(addr=region.addr, virtaddr=region.virtaddr, length=overflow))
            region.length -= overflow

        if region.length != 0:
            log.error("Length error: {region.length}")

        log.debug("..")

    def __str__( self ) -> str:
        """
        Recursively crawl this table to generate a pretty-printable string.
        """
        skip = 0
        last_string = ""
        last_comment = ""

        margin = " " * (self.level - mmu.start_level) * 1
        margin2 = " " * (4 - self.level) * 1
        string = f"{margin}level {self.level} table @ {args.ttb} + {hex(self.addr)}\n"
        for k in sorted(list(self.entries.keys())):
            entry = self.entries[k]

            if type(entry) is Table:
                if skip > 0:
                    if skip > 1:
                        string += '{}        ...\n'.format(margin)
                    string += last_string

                header = "{}[{:>4}]".format(margin, k)
                nested_table = str(entry)
                hyphens = "-" * (len(nested_table.splitlines()[0]) - len(header))
                string += f"{header}" + hyphens + f"\\\n{nested_table}"
                skip = 0
                last_string = ""
                last_comment = ""
            else:
                mt = entry.memory_type & 3
                memtype = "S" if (entry.memory_type & 4) else " "
                if mt == mmap.MEMORY_TYPE.DEVICE:
                    memtype += "DE"
                elif mt == mmap.MEMORY_TYPE.CACHE_WB:
                    memtype += "WB"
                elif mt == mmap.MEMORY_TYPE.CACHE_WT:
                    memtype += "WT"
                else:
                    memtype += "NC"

                rights=""
                rights  = "XN" if entry.ap_type & mmap.AP_TYPE.SXN else " X"
                rights += " XN" if entry.ap_type & mmap.AP_TYPE.UXN else "  X"
                if (entry.ap_type & 3) == mmap.AP_TYPE.SRW_UNA:
                    rights += " WR UN"
                elif (entry.ap_type & 3) == mmap.AP_TYPE.SRW_URW:
                    rights += " RW RW"
                elif (entry.ap_type & 3) == mmap.AP_TYPE.SRO_UNA:
                    rights += " RO UN"
                else:
                    rights += " RO RO"
                rights += " -" if entry.ap_type & mmap.AP_TYPE.NS else " S"

                rights += " G" if entry.memory_type & mmap.MEMORY_TYPE.GLOBAL else " -"

                if (last_comment != entry.comment):
                    if skip > 0:
                        if skip > 1:
                            string += '{}        ...\n'.format(margin)
                        string += last_string

                    string += "{}{}       --- {} ---\n".format(margin,margin2,entry.comment)
                    x = "{}[{:>4}]{}{:>010}-{:>010}=>{:>010}-{:>010},".format(
                        margin,
                        k,
                        margin2,
                        hex(entry.addr)[2:],
                        hex(entry.addr + entry.length - 1)[2:],
                        hex(entry.virtaddr)[2:],
                        hex(entry.virtaddr + entry.length - 1)[2:])

                    offset = " " * (63-len(x)-8)
                    string += x+"{} {} {}\n".format(
                        offset,
                        memtype,rights)

                    skip = 0;
                    last_string = ""
                    last_comment = entry.comment
                else:
                    skip += 1
                    x = "{}[{:>4}]{}{:>010}-{:>010}=>{:>010}-{:>010},".format(
                        margin,
                        k,
                        margin2,
                        hex(entry.addr)[2:],
                        hex(entry.addr + entry.length - 1)[2:],
                        hex(entry.virtaddr)[2:],
                        hex(entry.virtaddr + entry.length - 1)[2:])

                    offset = " " * (63-len(x)-8)
                    last_string = x+"{} {} {}\n".format(
                        offset,
                        memtype, rights)

        if skip > 0:
            if skip > 1:
                string += '{}        ...\n'.format(margin)
            string += last_string

        return string


    @classmethod
    def usage( cls ) -> str:
        """
        Generate memory allocation usage information for the user.
        """
        string  = f"This memory map requires a total of {len(cls._allocated)} translation tables.\n"
        string += f"Each table occupies {args.tg_str} of memory ({hex(args.tg)} bytes).\n"
        string += f"The buffer pointed to by '{args.ttb}' is therefore {len(cls._allocated)}x{args.tg_str} = {hex(args.tg * len(cls._allocated))} bytes long."
        return string


root = Table()
[root.map(r) for r in mmap.regions]
