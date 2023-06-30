"""
Copyright (c) 2019 Ash Wilding. All rights reserved.
          (c) 2021 42Bastian Schick

SPDX-License-Identifier: MIT
"""

"""
Parse command-line arguments.
"""
from . import args

"""
Determine MMU constants incl. runtime values for ttbr0, mair, tcr, and sctlr.
"""
from . import mmu

"""
Parse memory map file into list of non-overlapping Region objects sorted by
ascending base address.
"""
from . import mmap

"""
Generate abstract translation tables in the form of Table objects containing
both Region objects and pointers to next-level Table objects.
"""
from . import table

"""
Generate assembly to program the MMU and translation tables at runtime.
"""
from . import codegen

"""
Write generated assembly to output file.
"""
try:
    with open(args.o, "w") as f:
        f.write(codegen.output)
except OSError as e:
    import sys
    log.error(e)
    sys.exit(e.errno if hasattr(e, "errno") else 1)
