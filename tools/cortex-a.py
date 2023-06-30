# Cortex-A register decoders for GDB
#
# From gdb, run "source script/cortex-a.py"
#
# Commands:
#   armv8a-exception - Displays exception class and ISR data
#   armv8a-tcr-el1   - Displays register value and fields
#   armv8a-hcr-el2   - Displays register value and fields
#
# Settings:
#

import gdb

def print_bits(value, bitfield):
    low_bit, bit_count, label = bitfield
    field = (value >> low_bit) & ((1 << bit_count) - 1)
    if bit_count > 1:
        bitfield = "[{}:{}]".format(low_bit + bit_count - 1, low_bit)
    else:
        bitfield = "[{}]".format(low_bit)
    padded_binary = "{:0{}b}".format(field, bit_count)
    print("{:<8}{:<8} 0b{}".format(bitfield, label, padded_binary))

def print_bitfields(value, bitfields):
    [print_bits(value, x) for x in bitfields]

class Armv8ARegister(gdb.Command):
    def __init__(self, cmd, reg, label, bitfields):
        super (Armv8ARegister, self).__init__(cmd, gdb.COMMAND_DATA)
        self.reg = reg
        self.label = label
        self.bitfields = bitfields

    def invoke(self, arg, from_tty):
        frame = gdb.selected_frame()
        value = int(frame.read_register(self.reg))
        print("{}: 0x{:08x}".format(self.label, value))
        print_bitfields(value, self.bitfields)

Armv8ARegister("armv8a-tcr-el1",
               "TCR_EL1",
               "Translation Control Register EL1",
               ((61, 1, "MTX1"),
                (60, 1, "MTX0"),
                (59, 1, "DS"),
                (58, 1, "TCMA1"),
                (57, 1, "TCMA0"),
                (56, 1, "E0PD1"),
                (55, 1, "E0PD0"),
                (54, 1, "NFD1"),
                (53, 1, "NFD0"),
                (52, 1, "TBID1"),
                (51, 1, "TBID0"),
                (50, 1, "HWU162"),
                (49, 1, "HWU161"),
                (48, 1, "HWU160"),
                (47, 1, "HWU159"),
                (46, 1, "HWU062"),
                (45, 1, "HWU061"),
                (44, 1, "HWU060"),
                (43, 1, "HWU059"),
                (42, 1, "HPD1"),
                (41, 0, "HPD0"),
                (40, 1, "HD"),
                (39, 1, "HA"),
                (38, 1, "TBI1"),
                (37, 1, "TBI0"),
                (36, 1, "AS"),
                (32, 3, "IPS"),
                (30, 2, "TG1"),
                (28, 2, "SH1"),
                (26, 2, "ORGN1"),
                (24, 2, "IRGN1"),
                (23, 1, "EPD1"),
                (22, 1, "A1"),
                (16, 6, "T1SZ"),
                (14, 2, "TG0"),
                (12, 2, "SH0"),
                (10, 2, "ORGN0"),
                ( 8, 2, "IRGN0"),
                ( 7, 1, "EPD0"),
                ( 0, 6, "T0SZ")))

Armv8ARegister("armv8a-hcr-el2",
               "HCR_EL2",
               "Hypervisor Control Register EL2",
               ((60, 3, "TWEDEL"),
                (59, 1, "TWEDEn"),
                (58, 1, "TID5"),
                (57, 1, "DCT"),
                (56, 1, "ATA"),
                (55, 1, "TTLBOS"),
                (54, 1, "TTLBIS"),
                (53, 1, "EnSCXT"),
                (52, 1, "TOCU"),
                (51, 1, "AMVOFFEN"),
                (50, 1, "TICAB"),
                (49, 1, "TID4"),
                (48, 1, "GPF"),
                (47, 1, "FIEN"),
                (46, 1, "FWB"),
                (45, 1, "NV2"),
                (44, 1, "AT"),
                (42, 1, "NV1"),
                (41, 1, "API"),
                (40, 1, "APK"),
                (39, 1, "TME"),
                (38, 1, "MIOCNCE"),
                (37, 1, "TEA"),
                (36, 1, "TERR"),
                (35, 1, "TLOR"),
                (34, 1, "E2H"),
                (33, 1, "ID"),
                (32, 1, "CD"),
                (31, 1, "RW"),
                (30, 1, "TRVM"),
                (29, 1, "HCR"),
                (28, 1, "TDZ"),
                (27, 1, "TGE"),
                (26, 1, "TVM"),
                (25, 1, "TTLB"),
                (24, 1, "TPU"),
                (23, 1, "Bit[23]"),
                (22, 1, "TSW"),
                (21, 1, "TACR"),
                (20, 1, "TIDCP"),
                (19, 1, "TSC"),
                (18, 1, "TID3"),
                (17, 1, "TID2"),
                (16, 1, "TID1"),
                (15, 1, "TID0"),
                (14, 1, "TWE"),
                (13, 1, "TWI"),
                (12, 1, "DC"),
                (10, 2, "BSU"),
                ( 9, 1, "FB"),
                ( 8, 1, "VSE"),
                ( 7, 1, "VI"),
                ( 6, 1, "VF"),
                ( 5, 1, "AMO"),
                ( 4, 1, "IMO"),
                ( 3, 1, "FMO"),
                ( 2, 1, "PTW"),
                ( 1, 1, "SWIO"),
                ( 0, 1, "VM")))

class DataAbortDecode():
    data_abort_dfsc = {
        0b000000: "Address size fault, level 0 of translation or translation table base register",
        0b000001: "Address size fault, level 1",
        0b000010: "Address size fault, level 2",
        0b000011: "Address size fault, level 3",
        0b000100: "Translation fault, level 0",
        0b000101: "Translation fault, level 1",
        0b000110: "Translation fault, level 2",
        0b000111: "Translation fault, level 3",
        0b001001: "Access flag fault, level 1",
        0b001010: "Access flag fault, level 2",
        0b001011: "Access flag fault, level 3",
        0b001000: "Access flag fault, level 0",
        0b001100: "Permission fault, level 0",
        0b001101: "Permission fault, level 1",
        0b001110: "Permission fault, level 2",
        0b001111: "Permission fault, level 3",
        0b010000: "Synchronous External abort, not on TT walk or hardware update of translation table",
        0b010001: "Synchronous Tag Check Fault",
        0b010011: "Synchronous External abort on TT walk or hardware update of translation table, level -1",
        0b010100: "Synchronous External abort on TT walk or hardware update of translation table, level 0",
        0b010101: "Synchronous External abort on TT walk or hardware update of translation table, level 1",
        0b010110: "Synchronous External abort on TT walk or hardware update of translation table, level 2",
        0b010111: "Synchronous External abort on TT walk or hardware update of translation table, level 3",
        0b011000: "Synchronous parity or ECC error on memory access, not on TT walk",
        0b011011: "Synchronous parity or ECC error on memory access on TT walk or hardware update of translation table, level -1",
        0b011100: "Synchronous parity or ECC error on memory access on TT walk or hardware update of translation table, level 0",
        0b011101: "Synchronous parity or ECC error on memory access on TT walk or hardware update of translation table, level 1",
        0b011110: "Synchronous parity or ECC error on memory access on TT walk or hardware update of translation table, level 2",
        0b011111: "Synchronous parity or ECC error on memory access on TT walk or hardware update of translation table, level 3",
        0b100001: "Alignment fault",
        0b100011: "Granule Protection Fault on TT walk or hardware update of translation table, level -1",
        0b100100: "Granule Protection Fault on TT walk or hardware update of translation table, level 0",
        0b100101: "Granule Protection Fault on TT walk or hardware update of translation table, level 1",
        0b100110: "Granule Protection Fault on TT walk or hardware update of translation table, level 2",
        0b100111: "Granule Protection Fault on TT walk or hardware update of translation table, level 3",
        0b101000: "Granule Protection Fault, not on TT walk or hardware update of translation table",
        0b101001: "Address size fault, level -1",
        0b101011: "Translation fault, level -1",
        0b110000: "TLB conflict abort",
        0b110001: "Unsupported atomic hardware update fault",
        0b110100: "IMPLEMENTATION DEFINED fault (Lockdown)",
        0b110101: "IMPLEMENTATION DEFINED fault (Unsupported Exclusive or Atomic access)",
    }
    bitfields = ((24, 1, "ISV"),
                 (22, 2, "SAS"),
                 (21, 1, "SSE"),
                 (16, 5, "SRT"),
                 (15, 1, "SF"),
                 (14, 1, "AR"),
                 (13, 1, "VNCR"),
                 (10, 1, "FNV"),
                 ( 9, 1, "EA"),
                 ( 8, 1, "CM"),
                 ( 7, 1, "S1ptw"),
                 ( 6, 1, "WNR"),
                 ( 0, 6, "DFSC"))

    def decode_iss(self, frame, iss):
        print_bitfields(iss, self.bitfields)
        isv = (iss >> 23) & 0x1
        if isv:
            sas = (iss >> 22) & 0x3
            access_sizes = ("Byte", "Halfword", "Word", "Doubleword")
            print("Access size: ", access_sizes[sas])

            sse = (iss >> 21) & 0x1
            print("Sign extended: ", "Yes" if sse else "No")

            srt = (iss >> 16) & 0x1f
            sf = (iss >> 15) & 0x1
            print("Register: ", hex(srt), "64-bit" if sf else "32-bit")
        fnv = (iss >> 9) & 0x1
        if not fnv:
            value = int(frame.read_register("FAR_EL1"))
            print("        FAR      {:08x}".format(value))
        dfsc = iss & 0x3f
        if dfsc in self.data_abort_dfsc:
            print("                ", self.data_abort_dfsc[dfsc])

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

    bitfields = ((14, 1, "PFV"),
                 (11, 2, "SET"),
                 (10, 1, "FnV"),
                 ( 9, 1, "EA"),
                 ( 7, 1, "S1ptw"),
                 ( 0, 6, "IFSC"))

    def decode_iss(self, frame, iss):
        print_bitfields(iss, self.bitfields)
        fnv = (iss >> 9) & 0x1
        if not fnv:
            value = int(frame.read_register("FAR_EL1"))
            print("        FAR      {:08x}".format(value))
        ifsc = iss & 0x3f
        if ifsc in self.instruction_abort_ifsc:
            print("                ", self.instruction_abort_ifsc[ifsc])

class Armv8AException(Armv8ARegister):
    def __init__(self):
        super (Armv8AException, self).__init__ ("armv8a-exception",
                                                "ESR_EL1",
                                                "Exception Syndrome Register EL1",
                                                ((32, 24, "ISS2"),
                                                 (26,  6, "EC"),
                                                 (25,  1, "IL"),
                                                 ( 0, 24, "ISS")))

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
            print("No exception detected in ESR_EL1")
            return None

        super().invoke(arg, from_tty)

        ec = (value >> 26) & 0x3ff
        if ec in self.error_codes:
            print("                ", self.error_codes[ec])
        iss = value & 0xffffff
        if ec in self.decoders:
            self.decoders[ec].decode_iss(frame, iss)

Armv8AException()
