# Forth word debugging tools for use in gdb
#
# From gdb, run "source tools/words.py"
#
# Glossary:
#   latest           - print the address of the most recently defined word
#   print_word       - print info about the word at the given address
#   find_word        - locate a word by name (string)
#   find_word_around - locate a word that contains the given address
#

import gdb
import re

def get_symbol_address(symbol_name):
    output = gdb.execute("info variables", to_string=True)
    pattern = rf"(0x[0-9a-fA-F]+)\s+{re.escape(symbol_name)}"
    match = re.search(pattern, output, re.MULTILINE)

    if match:
        address = match.group(1)
        return int(address, 16)
    else:
        return None

def word_name(addr):
    inferior = gdb.selected_inferior()
    mem = inferior.read_memory(addr, 40)
    namelen = int.from_bytes(mem[9])
    return str(mem[10:10+namelen], 'latin-1')

def print_word(addr):
    # word header is 40 bytes long
    # 0 - 7: link address
    #     8: flags
    #     9: name length
    # 10-40: name chars, padded with ','
    inferior = gdb.selected_inferior()
    mem = inferior.read_memory(addr, 40)
    link = deref(addr)
    flags = int.from_bytes(mem[8])
    if (flags & 0x80):
        iflag = 'i'
    else:
        iflag = ' '
    if (flags & 0x20):
        hflag = 'h'
    else:
        hflag = ' '
    namelen = int.from_bytes(mem[9])
    name = str(mem[10:10+namelen], 'latin-1').ljust(40)

    print('0x%x\t%c %c %s (link 0x%x)' % (addr, iflag, hflag, name, link))

def deref(addr):
    inf = gdb.selected_inferior()
    mem = inf.read_memory(addr, 8)
    return int.from_bytes(mem, byteorder='little')

def word_before(addr):
    return deref(addr)

def get_latest():
    p_latest = get_symbol_address('var_latest')

    if p_latest is None:
        raise ValueError("Cannot locate var_latest")
    else:
        return deref(p_latest)

class PrintWord(gdb.Command):
    def __init__(self):
        super (PrintWord, self).__init__('print_word', gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        addr = gdb.parse_and_eval(argv[0]).cast(gdb.lookup_type('void').pointer())

        print_word(addr)

class Latest(gdb.Command):
    def __init__(self):
        super (Latest, self).__init__('latest', gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        print(hex(get_latest()))

class FindWord(gdb.Command):
    def __init__(self):
        super(FindWord,self).__init__('find_word', gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        target = gdb.string_to_argv(arg)[0]

        p_latest = get_latest()

        if p_latest is None:
            print("Cannot locate var_latest")
        else:
            prev = p_latest

            while prev != 0:
                curr = prev
                prev = word_before(curr)

                name = word_name(curr)
                if name == target:
                    print_word(curr)
                    return
            print(f"Cannot locate {target}")

class WordAround(gdb.Command):
    def __init__(self):
        super(WordAround,self).__init__('find_word_around', gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        addr = gdb.parse_and_eval(argv[0]).cast(gdb.lookup_type('void').pointer())

        p_latest = get_latest()

        if p_latest is None:
            print("Cannot locate var_latest")
        else:
            prev = p_latest

            while prev != 0:
                curr = prev
                prev = word_before(curr)

                if prev == 0:
                    break
                
                if prev <= addr < curr:
                    print_word(prev)
                    return
            print(f"Cannot locate word around {addr}")

            
PrintWord()
Latest()
FindWord()
WordAround()
