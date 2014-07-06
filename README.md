# Raspberry Pi JonesFORTH O/S

A bare-metal operating system for Raspberry Pi,
based on _Jonesforth-ARM_ at <https://github.com/M2IHP13-admin/JonesForth-arm>.

_Jonesforth-ARM_ is an ARM port, by M2IHP'13 class members listed in `AUTHORS`, of _x86 JonesForth_.

_x86 JonesForth_ is a Linux-hosted FORTH presented in a Literate Programming style
by Richard W.M. Jones <rich@annexia.org> originally at <http://annexia.org/forth>.
Comments embedded in the original provide an excellent FORTH implementation tutorial.
See the `/annexia/` directory for a copy of this original source.

The algorithm for our unsigned DIVMOD instruction is extracted from 'ARM
Software Development Toolkit User Guide v2.50' published by ARM in 1997-1998

Firmware files to make bootable images are maintained at <https://github.com/raspberrypi/firmware>.
See the `/firmware/` directory for local copies used in the build process.

## What is this ?

_pijFORTHos_ is a bare-metal FORTH interpreter for the Raspberry Pi.
It follows the general strategy given by the excellent examples at <https://github.com/dwelch67/raspberrypi>.
A bootloader is built in, supporting XMODEM uploads of new bare-metal kernel images.

The interpreter uses the RPi miniUART as a console (115200 baud, 8 data bits, no parity, 1 stop bit).
If you have _pijFORTHos_ on an SD card in the RPi, 
you can connect it to another machine (even another RPi) using a USB-to-Serial cable <http://www.adafruit.com/products/954>.
When the RPi is powered on (I provide power through the cable),
a terminal program on the host machine allows access to the FORTH console.

## Build and run instructions

If you are building on the RPi, just type:

    $ make clean all

Then, copy the firmware and kernel to a blank SD card:

    $ cp firmware/* /media/<SD-card>/
    $ cp kernel.img /media/<SD-card>/

Put the prepared SD card into the RPi, connect the USB-to-Serial cable, and power-up to the console.

## FORTH Definitions

Each dialect of FORTH has its own definitions.
Development in FORTH involves extending the vocabulary with words specific to your application.
Most pre-defined words follow tradtional standards and conventions, but see the tables below for details.

### Built-in FORTH Variables

Variables are words that place an address on the stack.
Use `@` (fetch) and `!` (store) to read/write the current value of a variable.
The following variable are pre-defined in _pijFORTHos_

| Variable | Description |
|----------|-------------|
| `STATE` | Is the interpreter executing code (0), or compiling a word (non-zero)? |
| `HERE` | Address of the next free byte of memory.  When compiling, compiled words go here. |
| `LATEST` | Address of the latest (most recently defined) word in the dictionary. |
| `S0` | Address of the top of the parameter/data stack. |
| `BASE` | The current base for printing and reading numbers. |

Here is an example using the `BASE` variable:

    BASE @          \ read the current value of BASE (to restore later)
    16 BASE !       \ switch to hexadecimal
    8000 100 DUMP   \ hexdump 256 bytes starting at 0x8000
    BASE !          \ restore the orignial value of BASE (from the stack)

### Built-in FORTH Constants

Constants are words that place pre-defined value on the stack.
They are useful mnemonics and help us avoid "magic" numbers in our code.
The following constants are pre-defined in _pijFORTHos_

| Variable | Description |
|----------|-------------|
| `VERSION` | The version number of this FORTH. |
| `R0` | Address of the top of the return stack. |
| `DOCOL` | Address of DOCOL (the word interpreter). |
| `PAD` | Address of the 128-byte scratch-pad buffer (top of `HERE` memory). |
| `F_IMMED` | The IMMEDIATE flag's actual value. |
| `F_HIDDEN` | The HIDDEN flag's actual value. |
| `F_LENMASK` | The length mask in the flags/len byte. |

Given the relationship between `HERE` and `PAD`, 
the following calculates the number of free memory cells available:

    PAD        \ the base of PAD is the end of available program memory
    HERE @ -   \ subtract the base address of free memory
    4 /        \ divide by 4 to convert bytes to (32-bit) cells

### Built-in FORTH Words

The following words are pre-defined in _pijFORTHos_ 

| Word | Stack | Description |
|------|-------|-------------|
| `DROP` | ( a -- ) | drop the top element of the stack |
| `SWAP` | ( a b -- b a ) | swap the two top elements |
| `DUP` | ( a -- a a ) | duplicate the top element |
| `OVER` | ( a b c -- a b c b ) | push the second element on top |
| `ROT` | ( a b c -- b c a ) | stack rotation |
| `-ROT` | ( a b c -- c a b ) | backwards rotation |
| `2DROP` | ( a b -- ) | drop the top two elements of the stack |
| `2DUP` | ( a b -- a b a b ) | duplicate top two elements of stack |
| `2SWAP` | ( a b c d -- c d a b ) | swap top two pairs of elements of stack |
| `?DUP` | ( 0 -- 0 &#124; a -- a a ) | duplicate if non-zero |
| `1+` | ( a -- a+1 ) | increment the top element |
| `1-` | ( a -- a-1 ) | decrement the top element |
| `4+` | ( a -- a+4 ) | increment by 4 the top element |
| `4-` | ( a -- a-4 ) | decrement by 4 the top element |
| `+` | ( a b -- a+b ) | addition |
| `-` | ( a b -- a-b ) | subtraction |
| `*` | ( a b -- a*b ) | multiplication |
| `=` | ( a b -- p ) | where p is 1 when a == b, 0 otherwise |
| `<>` | ( a b -- p ) | where p = a <> b |
| `<` | ( a b -- p ) | where p = a < b |
| `>` | ( a b -- p ) | where p = a > b |
| `<=` | ( a b -- p ) | where p = a <= b |
| `>=` | ( a b -- p ) | where p = a >= b |
| `0=` | ( a -- p ) | where p = a == 0 |
| `0<>` | ( a -- p ) | where p = a <> 0 |
| `0<` | ( a -- p ) | where p = a < 0 |
| `0>` | ( a -- p ) | where p = a > 0 |
| `0<=` | ( a -- p ) | where p = a <= 0 |
| `0>=` | ( a -- p ) | where p = a >= 0 |
| `AND` | ( a b -- a&amp;b ) | bitwise and |
| `OR` | ( a b -- a&#124;b ) | bitwise or |
| `XOR` | ( a b -- a^b ) | bitwise xor |
| `INVERT` | ( a -- ~a ) | bitwise not |
| `LIT` | ( -- x ) | used to compile literals in FORTH word |
| `!` | ( value addr -- ) | write value at addr |
| `@` | ( addr -- value ) | read value from addr |
| `+!` | ( amount addr -- ) | add amount to value at addr |
| `-!` | ( amount addr -- ) | subtract amount to value at addr |
| `C!` | ( c addr -- ) | write byte c at addr |
| `C@` | ( addr -- c ) | read byte from addr |
| `CMOVE` | ( src dst len -- ) | copy len bytes from src to dst |
| `>R` | (S: a -- ) (R: -- a ) | move the top element from the data stack to the return stack |
| `R>` | (S: -- a ) (R: a -- ) | move the top element from the return stack to the data stack |
| `RDROP` | (R: a -- ) | drop the top element from the return stack |
| `RSP@` | ( -- addr ) | get return stack pointer |
| `RSP!` | ( addr -- ) | set return stack pointer |
| `DSP@` | ( -- addr ) | get data stack pointer |
| `DSP!` | ( addr -- ) | set data stack pointer |
| `KEY` | ( -- c ) | read a character from the console |
| `EMIT` | ( c -- ) | write character c to the console |
| `WORD` | ( -- addr len ) | read next word from stdin |
| `NUMBER` | ( addr len -- n e ) | convert string to number n, with e unparsed characters |
| `FIND` | ( addr len -- dictionary_addr &#124; 0 ) | search dictionary for entry matching string |
| `>CFA` | ( dictionary_addr -- executable_addr ) | get execution address from dictionary entry |
| `>DFA` | ( dictionary_addr -- data_field_addr ) | get data field address from dictionary entry |
| `CREATE` | ( addr len -- ) | create a new dictionary entry |
| `,` | ( n -- ) | write the top element from the stack at HERE |
| `[` | ( -- ) | change interpreter state to Immediate mode |
| `]` | ( -- ) | change interpreter state to Compilation mode |
| `:` | ( -- ) | define a new FORTH word |
| `;` | ( -- ) | end FORTH word definition |
| `IMMEDIATE` | ( -- ) | set IMMEDIATE flag of last defined word |
| `HIDDEN` | ( dictionary_addr -- ) | set HIDDEN flag of a word |
| `HIDE` | ( -- ) | hide definition of  next read word |
| `'` | ( -- xt ) | return the codeword address of next read word (compile only) |
| `BRANCH` | ( -- ) | change FIP by offset which is found in the next codeword |
| `0BRANCH` | ( p -- ) | branch if the top of the stack is zero |
| `LITSTRING` | ( -- s ) | as LIT but for strings |
| `TELL` | ( addr len -- ) | write a string to the console |
| `QUIT` | ( -- ) | the first word to be executed |
| `/MOD` | ( a b -- r q ) | where a = q * b + r |
| `S/MOD` | ( a b -- r q ) | alternative signed /MOD using Euclidean division |
| `CHAR` | ( -- c ) | ASCII code of the first character of the next word |
| `UPLOAD` | ( -- addr len ) | XMODEM file upload to memory image |
| `DUMP` | ( addr len -- ) | pretty-printed memory dump |
| `BOOT` | ( addr len -- ) | boot from memory image (see UPLOAD) |
| `EXECUTE` | ( xt -- ) | jump to the address on the stack |

### Supplemental FORTH Words

Many standard words can be defined using the built-in primitives shown above.
The file `jonesforth.f` contains important and useful definitions.
It also serves as a significant corpus of example FORTH code.
The entire contents of this file can simply be copy-and-pasted 
into the terminal session connected to the _pijFORTHos_ console.
A welcome message is displayed by the code at the end of the file.
The following additional words are defined in `jonesforth.f` 

| Word | Stack | Description |
|------|-------|-------------|
| / | ( -- ) | /MOD SWAP DROP |
| MOD | ( -- ) | /MOD DROP |
| '\n' | ( -- ) | 10 |
| BL | ( -- ) | 32 |
| CR | ( -- ) | '\n' EMIT \ print newline |
| SPACE | ( -- ) | BL EMIT \ print space |
| NEGATE | ( -- ) | 0 SWAP - |
| TRUE | ( -- ) | 1 |
| FALSE | ( -- ) | 0 |
| NOT | ( -- ) | 0= |
| UNUSED | ( -- n ) | calculate the number of cells remaining in the user memory (data segment). |

## Memory Organization

_TODO_

### Bootloader

_TODO_
