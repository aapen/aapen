"""
Copyright (c) 2019 Ash Wilding. All rights reserved.
          (c) 2021 42Bastian Schick

SPDX-License-Identifier: MIT
"""

# Standard Python deps
from enum import Enum
from enum import IntEnum
import errno
import re
import sys
from dataclasses import dataclass

# Internal deps
from . import args
from . import log

# External deps
from intervaltree import Interval, IntervalTree

class AP_TYPE(IntEnum):
        NS  = 16,
        UXN = 8,
        SXN = 4,
        SRW_UNA = 0,   # implies User no access
        SRW_URW = 1,   # implies SRW
        SRO_UNA = 2,   # implies User no access
        SRO_URO = 3    # implies SRO

class MEMORY_TYPE(IntEnum):
        DEVICE = 0,
        CACHE_WB = 1,
        CACHE_WT = 2,
        NO_CACHE = 3,
        SHARED = 4,
        GLOBAL = 8

@dataclass
class Region:
    """
    Class representing a single region in the memory map.
    """

    lineno: int                    # line number in source memory map file
    comment: str                   # name/comment e.g. DRAM, GIC, UART, ...
    addr: int                      # base address
    virtaddr: int                  # virtual base addr
    length: int                    # length in bytes
    memory_type: MEMORY_TYPE       # True for Device-nGnRnE, False for Normal WB RAWA
    ap_type: AP_TYPE               # Access right
    num_contig = 1


    def copy( self, **kwargs ):
        """
        Create a duplicate of this Region.
        Use kwargs to override this region's corresponding properties.
        """
        region = Region(self.lineno,self.comment, self.addr, self.virtaddr, self.length, self.memory_type, self.ap_type)
        for kw,arg in kwargs.items():
            region.__dict__[kw] = arg
        return region


    def __str__( self ):
        """
        Override default __str__ to print addr and length in hex format.
        """
        return "Region(lineno={}, comment='{}', addr={}, virtaddr={}, length={}, memory_type={}".format(
            self.lineno, self.comment, hex(self.addr), hex(self.virtaddr), hex(self.length), self.memory_type, self.ap_type
        )


class MemoryMap():
    """
    Class representing the user's entire specified memory map.
    This is a wrapper around chaimleib's intervaltree library.
    """

    def __init__( self, map_file:str ):
        self._ivtree = IntervalTree()

        if map_file == "stdin" :
                map_file_handle=sys.stdin
        else:
                try:
                        map_file_handle= open(map_file, "r")

                except OSError as e:
                        log.error(f"failed to open map file: {e}")
                        sys.exit(e.errno)

        with map_file_handle:
                map_file_lines = map_file_handle.readlines()

                """
                Loop through each line in the map file.
                """
                for lineno,line in enumerate(map_file_lines):
                    line = line.strip()
                    log.debug()
                    log.debug(f"parsing line {lineno}: {line}")

                    if len(line) == 0:
                        continue

                    if line[0] == '#':
                        continue

                    if line.startswith('//'):
                        continue

                    def abort_bad_region( msg:str, variable ) -> None:
                        """
                        Pretty-print an error message and force-exit the script.
                        """
                        log.error(f"in {map_file_handle} on line {lineno+1}: bad region {msg}: {variable}")
                        log.error(f"    {line}")
                        log.error(f"    {' '*line.find(variable)}{'^'*len(variable)}")
                        sys.exit(errno.EINVAL)

                    """
                    Ensure correct number of fields have been specified.
                    """
                    split_line = line.split(",")
                    if len(split_line) < 6:
                        abort_bad_region("format: incomplete", line)
                    if len(split_line) > 6:
                        abort_bad_region("format: unexpected field(s)", line[line.find(split_line[4]):])
                    (addr, virtaddr, length, memtype, rights, comment) = split_line
                    addr = addr.strip()
                    virtaddr = virtaddr.strip()
                    if virtaddr == "":
                        virtaddr = addr
                    length = length.strip()
                    memtype = memtype.strip()
                    split_memtype = memtype.split(":")
                    if len(split_memtype) > 3:
                        abort_bad_region("To many options", line)
                    memtype = split_memtype[0]

                    split_rights = rights.split(":")
                    if len(split_rights) < 1:
                        abort_bad_region("Missing rights", line)
#                    if len(split_rights) > 2:
#                        abort_bad_region("To many rights", line)

                    comment = comment.strip()

                    """
                    Parse region base address.
                    """
                    log.debug(f"parsing base address: {addr}")
                    try:
                        addr = eval(addr)
                    except SyntaxError:
                        abort_bad_region("base address", addr)

                    log.debug(f"parsing virtual base address: {virtaddr}")
                    try:
                        virtaddr = eval(virtaddr)
                    except SyntaxError:
                        abort_bad_region("virtual address", virtaddr)

                    if addr > (1 << args.tsz):
                        abort_bad_region("out address too largs", addr)

                    if virtaddr > (1 << args.tsz):
                        abort_bad_region("VA address too largs", hex(virtaddr))

                    """
                    Parse region length.
                    """
                    log.debug(f"parsing length: {length}")
                    length1 = re.sub(r"(\d+)K","(\\1*1024)", length)
                    length1 = re.sub(r"(\d+)M","(\\1*1024*1024)", length1)
                    length1 = re.sub(r"(\d+)G","(\\1*1024*1024*1024)", length1)
                    length1 = re.sub(r"(\d+)T","(\\1*1024*1024*1024*1024)", length1)
                    try:
                        length = eval(length1)
                    except SyntaxError:
                        abort_bad_region("length", length1)

                    """
                    Fudge region to be mappable at chosen granule size.
                    """
                    misalignment = addr % args.tg
                    if misalignment:
                        addr = addr - misalignment
                        length = length + args.tg
                        log.debug("corrected misalignment, new addr={}, length={}".format(hex(addr), hex(length)))

                    misalignment = virtaddr % args.tg
                    if misalignment:
                        virtaddr = virtaddr - misalignment
                        log.debug("corrected misalignment, new addr={}, length={}".format(hex(addr), hex(length)))

                    overflow = length % args.tg
                    if overflow:
                        length = length + args.tg - overflow
                        log.debug("corrected overflow, new length={}".format(hex(length)))

                    """
                    Parse region attributes.
                    """
                    memory_type = 0
                    log.debug(f"parsing memory type: {memtype}")
                    for memtype in split_memtype:
                        memtype = memtype.strip()
                        if not memtype in ["DEVICE", "CACHE_WB", "CACHE_WT", "NO_CACHE", "GLOBAL", "SHARED" ]:
                            abort_bad_region("memory type", memtype)

                        if (memory_type & 3) and memtype in ["DEVICE", "CACHE_WB", "CACHE_WT", "NO_CACHE"]:
                            abort_bad_region("memory type", memtype)

                        if memtype == "DEVICE":
                            memory_type |= MEMORY_TYPE.DEVICE
                        elif memtype == "CACHE_WB":
                            memory_type |= MEMORY_TYPE.CACHE_WB
                        elif memtype == "CACHE_WT":
                            memory_type |= MEMORY_TYPE.CACHE_WT
                        elif memtype == "NO_CACHE":
                            memory_type |= MEMORY_TYPE.NO_CACHE
                        elif memtype == "SHARED":
                            memory_type |= MEMORY_TYPE.SHARED
                        else:
                            memory_type |= MEMORY_TYPE.GLOBAL

                    log.debug(f"{memory_type=}")

                    """
                    Parse access rights
                    """
                    ap_right = AP_TYPE.SXN|AP_TYPE.UXN
                    for ap in split_rights:
                        ap = ap.strip()
                        if not ap in ["SX", "UX", "SRW_UNA", "SRW_URW", "SRO_UNA", "SRO_URO", "NS", "GLOBAL"]:
                            abort_bad_region("access rights", ap)
                        if ap == "SX":
                            ap_right &= ~AP_TYPE.SXN
                        elif ap == "UX":
                            ap_right &= ~AP_TYPE.UXN
                        elif ap == "NS":
                            ap_right |= AP_TYPE.NS
                        elif ap == "SHARED":
                            ap_right |= AP_TYPE.SHARED
                        elif ap == "GLOBAL":
                            memory_type |= MEMORY_TYPE.GLOBAL
                        elif ap == "SRW_UNA":
                            if (ap_right & 3):
                                abort_bad_region("access rights", ap)
                            ap_right |= AP_TYPE.SRW_UNA
                        elif ap == "SRW_URW":
                            if (ap_right & 3):
                                abort_bad_region("access rights", ap)
                            ap_right |= AP_TYPE.SRW_URW
                        elif ap == "SRO_UNA":
                            if (ap_right & 3):
                                abort_bad_region("access rights", ap)
                            ap_right |= AP_TYPE.SRO_UNA
                        else:
                            if (ap_right & 3):
                                abort_bad_region("access rights", ap)
                            ap_right |= AP_TYPE.SRO_URO

                    if memory_type == MEMORY_TYPE.DEVICE and (ap_right >> 2) != 3:
                        abort_bad_region(": Device region not be SX or UX!",hex(ap_right))

                    """
                    Check for overlap with other regions.
                    """
                    log.debug(f"checking for overlap with existing regions")
                    overlap = sorted(self._ivtree[virtaddr:virtaddr+length])
                    if overlap:
                        log.error(f"in {map_file} on line {lineno+1}: region overlaps other regions")
                        log.error(f"    {line}")
                        log.error(f"the overlapped regions are:")
                        [log.error(f"    {map_file_lines[iv.data.lineno-1].strip()} (on line {iv.data.lineno})") for iv in overlap]
                        sys.exit(errno.EINVAL)

                    """
                    Add parsed region to memory map.
                    """
                    r = Region(lineno+1, comment, addr, virtaddr, length, memory_type, ap_right)
                    self._ivtree.addi(virtaddr, virtaddr+length, r)
                    log.debug(f"added {r}")



    def regions( self ):
        """
        Return list of Region objects sorted by ascending base address.
        """
        return list(map(lambda r: r[2], sorted(self._ivtree)))


regions = MemoryMap(args.i).regions()
