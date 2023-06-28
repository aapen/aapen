# Cortex-A register decoders for GDB
#
# From gdb, run "source script/cortex-a.py"
#
# Commands:
#   armv8a-exception <value of ESR> - Displays exception class and ISR data
#
# Settings:
#

import gdb
from curses.ascii import isgraph

class DataAbortDecode():
    def decode_iss(self, frame, iss):
        isv = (iss >> 23) & 0x1
        sas = (iss >> 21) & 0x3
        sse = (iss >> 20) & 0x1
        srt = (iss >> 15) & 0x1ff
        sf = (iss >> 14) & 0x1
        ar = (iss >> 13) & ox1
        vncr = (iss >> 12) & 0x1
        _set = (iss >> 10) & 0x3
        fnv = (iss >> 9) & 0x1
        ea = (iss >> 8) & 0x1
        cm = (iss >> 7) & 0x1
        s1ptw = (iss >> 6) & 0x1
        wnr = (iss >> 5) & 0x1
        dfsc = iss & 0x1ff
        if isv:
            access_sizes = ("Byte", "Haflword", "Word", "Doubleword")
            print("Access size: ", acecss_sizes[sas])
            print("Sign extended: ", "Yes" if sse else "No")
            print("Register: ", hex(str), "64-bit" if sf else "32-bit")
        if dfsc == 0b010000:
            print("Not on translation table walk")
            if not fnv:
                value = int(frame.read_register("FAR_EL2"))
                print("FAR ", hex(value))
        elif dfsc == 0b010001:
            print("tag check fault")
        elif dfsc == 0b100001:
            print("alignment fault")
        else:
            print(bin(dfsc))
        print(vncr, _set, fnv, ea, cm, s1ptw, wnr, dfsc)

class InstructionAbortDecode():
    instruction_abort_ifsc = {
        0b000000: "Address size fault, level 0 of translation or TTBR",
        0b000001: "Address size fault, level 1",
        0b000010: "Address size fault, level 2",
        0b000011: "Address size fault, level 3",
        0b000100: "Translation fault, level 0",
        0b000101: "Translation fault, level 1",
        0b000110: "Translation fault, level 2",
        0b000111: "Translation fault, level 3",
        0b001000: "Access flag fault, level 0",
        0b001001: "Access flag fault, level 1",
        0b001010: "Access flag fault, level 2",
        0b001011: "Access flag fault, level 3",
        0b001100: "Permission fault, level 0",
        0b001101: "Permission fault, level 1",
        0b001110: "Permission fault, level 2",
        0b001111: "Permission fault, level 3",
        0b010000: "Synchronous external abort, not on TT walk",
        0b010010: "Synchronous external abort on TT walk, level -2",
        0b010011: "Synchronous external abort on TT walk, level -1",
        0b010100: "Synchronous external abort on TT walk, level 0",
        0b010101: "Synchronous external abort on TT walk, level 1",
        0b010110: "Synchronous external abort on TT walk, level 2",
        0b010111: "Synchronous external abort on TT walk, level 3",
        0b011000: "Synchronous parity or ECC error on memory access, not on TT walk",
        0b011011: "Synchronous parity or ECC error on memory access, on TT walk, level -1",
        0b011100: "Synchronous parity or ECC error on memory access, on TT walk, level 0",
        0b011101: "Synchronous parity or ECC error on memory access, on TT walk, level 1",
        0b011110: "Synchronous parity or ECC error on memory access, on TT walk, level 2",
        0b011111: "Synchronous parity or ECC error on memory access, on TT walk, level 3",
        0b101000: "Granule protection fault, not on TT walk",
        0b100010: "Granule protection fault on TT walk, level -2",
        0b100011: "Granule protection fault on TT walk, level -1",
        0b100100: "Granule protection fault on TT walk, level 0",
        0b100101: "Granule protection fault on TT walk, level 1",
        0b100110: "Granule protection fault on TT walk, level 2",
        0b100111: "Granule protection fault on TT walk, level 3",
        0b101001: "Address size fault, level -1",
        0b101010: "Translation fault, level -2",
        0b101011: "Translation fault, level -1",
        0b101100: "Address size fault, level -2",
        0b110000: "TLB conflict abort",
        0b110001: "Unsupported atomic hardware update fault"
    }

    def decode_iss(self, frame, iss):
        pfv = (iss >> 14) & 0x1
        _set = (iss >> 10) & 0x3
        fnv = (iss >> 9) & 0x1
        ea = (iss >> 8) & 0x1
        s1ptw = (iss >> 6) & 0x1
        ifsc = iss & 0x1f

        print("[14]    PFV   ", bin(pfv))
        print("[12:11] SET   ", format(_set, "#04b"))
        print("[10]    FnV   ", bin(fnv))
        if not fnv:
            value = int(frame.read_register("FAR_EL1"))
            print("        FAR   ", format(value, "#018x"))
        print("[9]     EA    ", bin(ea))
        print("[7]     S1ptw ", bin(s1ptw))
        print("[5:0]   IFSC  ", format(ifsc, "#08b"), " (", hex(ifsc), ")")
        if ifsc in self.instruction_abort_ifsc:
            print("              ", self.instruction_abort_ifsc[ifsc])



class Armv8AException(gdb.Command):
    def __init__(self):
        super (Armv8AException, self).__init__ ("armv8a-exception", gdb.COMMAND_DATA)

    decoders = {
        0b100101: DataAbortDecode(),
        0b100001: InstructionAbortDecode()
    }

    error_codes = {
        0b000001: "Trapped WF*",
        0b000011: "Trapped MCR or MRC",
        0b000100: "Trapped MCRR or MRRC",
        0b000101: "Trapped MCR or MRC",
        0b000110: "Trapped LDC or STC",
        0b000111: "Trapped SIMD",
        0b001000: "Trapped VMRS",
        0b001001: "Trapped pointer authentication",
        0b001010: "Trapped LD64B or ST64B*",
        0b001100: "Trapped MRRC",
        0b001101: "Branch target exception",
        0b001110: "Illegal execution state",
        0b010001: "SVC instruction",
        0b010010: "HVC instruction",
        0b010011: "SMC instruction",
        0b010101: "SVC instruction",
        0b010110: "HVC instruction",
        0b010111: "SMC instruction",
        0b011000: "Trapped MRS, MSR, or system instruction",
        0b011001: "Trapped SVE",
        0b011010: "Trapped ERET",
        0b011100: "Failed pointer authentication",
        0b100000: "Instruction abort from lower level",
        0b100001: "Instruction abort from same level",
        0b100010: "PC alignment failure",
        0b100100: "Data abort from lower level",
        0b100101: "Data abort from same level",
        0b100110: "SP alignment fault",
        0b101000: "32-bit floating point exception",
        0b101100: "64-bit floating point exception",
        0b101111: "SError interrupt",
        0b110000: "Breakpoint from lower level",
        0b110001: "Breakpoint from same level",
        0b110010: "Software step from lower level",
        0b110011: "Software step from same level",
        0b110100: "Watch point from same level",
        0b110101: "Watch point from lower level",
        0b111000: "Breakpoint in aarch32 mode",
        0b1110101: "Vector catch in aarch32",
        0b111100: "BRK instruction in aarch64",
    }

    def invoke(self, arg, from_tty):
        frame = gdb.selected_frame()
        value = int(frame.read_register("ESR_EL1"))
        if value == 0:
            return None
        iss2 = (value >> 32) & 0x1ff
        ec = (value >> 26) & 0x3ff
        il = (value >> 25) & 0x1
        iss = value & 0xffffff

        print("[63:56] RES0  ")
        print("[55:32] ISS2  ", format(iss2, "#026b"), " (", hex(iss2), ")")
        print("[31:26] EC    ", format(ec, "#08b"),    " (", hex(ec),   ")")
        print("[25]    IL    ", bin(il))
        print("[24:0]  ISS   ", format(iss, "#027b"),  " (", hex(iss),  ")")

        if ec in self.error_codes:
            print("              ", self.error_codes[ec])

        if ec in self.decoders:
            self.decoders[ec].decode_iss(frame, iss)


Armv8AException()
