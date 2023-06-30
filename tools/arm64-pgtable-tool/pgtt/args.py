"""
Copyright (c) 2019 Ash Wilding. All rights reserved.
          (c) 2021 42Bastian Schick

SPDX-License-Identifier: MIT

Parse command-line arguments to be accessible by any other importing file in the
project. A module is only actually imported once per Python interpreter instance
so this code only runs once regardless of how many times it is later imported.
"""

# Standard Python deps
import argparse

_parser = argparse.ArgumentParser()

_parser.add_argument(
    "-i",
    metavar="SRC",
    help="input memory map file (stdin if not set)",
    type=str,
    default="stdin"
)

_parser.add_argument(
    "-no_mmuon",
    help="Do not generate mmu_on function",
    default=0,
    action="count"
)

_parser.add_argument(
    "-o",
    metavar="DST",
    help="output GNU assembly file (default mmu_setup.S)",
    type=str,
    default="mmu_setup.S"
)

_parser.add_argument(
    "-ttbr1",
    help="Use TTBR1 instead of TTBR0 (default)",
    action="count",
    default = 0
)

_parser.add_argument(
    "-ttb",
    help="desired translation table base address as symbol! (default mmu_table)",
    type=str,
    default="mmu_table"
)

_parser.add_argument(
    "-el",
    help="exception level (default: 1)",
    type=int,
    choices=[1,2,3],
    default=1,
)

_parser.add_argument(
    "-tg",
    help="translation granule (default: 4K)",
    type=str,
    # we accept also low-level for the lazy ones
    choices=["4K", "16K", "64K", "4k", "16k", "64k" ],
    default="4K",
)

_parser.add_argument(
    "-tsz",
    help="address space size (default: 40)",
    type=int,
    choices=[32,36,40,48],
    default=40,
)

_parser.add_argument(
    "-l",
    metavar="label",
    help="extend labels with a custom identifier",
    type=str,
    default=""
)

_parser.add_argument(
    "-v",
    help="verbose",
    action="count",
    default=0,
)

_parser.add_argument(
    "-d",
    help="enable debug output",
    action="count",
    default=0,
)

_args = _parser.parse_args()

i = _args.i
o = _args.o
ttb = _args.ttb
el = _args.el
tg_str = _args.tg.upper()
tg = {"4K":4*1024, "16K":16*1024, "64K":64*1024}[_args.tg.upper()]
tsz = _args.tsz
ttbr1 = _args.ttbr1 > 0
verbose = _args.v >= 1
debug = _args.d > 0
label = "_"+_args.l if _args.l != "" else ""
no_mmuon = _args.no_mmuon > 0
