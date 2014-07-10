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

Then, copy the firmware and kernel to a blank SD card, for example:

    $ cp firmware/* /media/<SD-card>/
    $ cp kernel.img /media/<SD-card>/

The end state for the SD card is to have a FAT32 filesystem on it with the following files

    kernel.img
    firmware/bootcode.bin
    firmware/start.elf

Put the prepared SD card into the RPi, connect the USB-to-Serial cable (for how to connect you can reference [RPi Serial Connection](http://elinux.org/RPi_Serial_Connection)), and power-up to the console.

To get to the console, you'll need to connect. Here are two ways to try:

    $ minicom -b 115200 -o -D <Port_Name>

Where `<Port_Name>` is something like `/dev/ttyUSB0` or similar (wherever you plugged in your USB-to-Serial cable).

Alternatively, if `minicom` is not working (this happened before), you could use screen:

    $ screen <Port_Name> 115200

Where `<Port_Name>` is, again, something like `/dev/ttyUSB0`.

The console will be waiting for an input, press `<ENTER>`. You should then see:

    pijFORTHos <version> sp=0x00008000

The FORTH REPL will be running, try typing:

    16 BASE !
    8000 100 DUMP

You should see something like:

    00008000  08 10 4f e2 01 d0 a0 e1  80 e0 9f e5 02 09 a0 e3  |..O.............|
    00008010  01 00 50 e1 44 06 00 0a  00 e0 a0 e1 7f 2c a0 e3  |..P.D........,..|
    00008020  f8 07 b1 e8 f8 07 a0 e8  20 20 52 e2 fb ff ff ca  |........  R.....|
    00008030  1e ff 2f e1 fe ff ff ea  1e ff 2f e1 00 10 80 e5  |../......./.....|
    00008040  1e ff 2f e1 00 00 90 e5  1e ff 2f e1 b0 10 c0 e1  |../......./.....|
    00008050  1e ff 2f e1 b0 00 d0 e1  1e ff 2f e1 00 10 c0 e5  |../......./.....|
    00008060  1e ff 2f e1 00 00 d0 e5  1e ff 2f e1 0e 00 a0 e1  |../......./.....|
    00008070  1e ff 2f e1 10 ff 2f e1  ff 5f 2d e9 f8 07 b1 e8  |../.../.._-.....|
    00008080  f8 07 a0 e8 20 20 52 e2  fb ff ff ca ff 9f bd e8  |....  R.........|
    00008090  34 80 00 00 14 0f 9f e5  00 d0 80 e5 10 bf 9f e5  |4...............|
    000080a0  10 0f 9f e5 10 1f 9f e5  00 00 81 e5 0c af 9f e5  |................|
    000080b0  04 00 9a e4 00 10 90 e5  11 ff 2f e1 04 a0 2b e5  |........../...+.|
    000080c0  04 a0 80 e2 04 00 9a e4  00 10 90 e5 11 ff 2f e1  |............../.|
    000080d0  04 a0 9b e4 04 00 9a e4  00 10 90 e5 11 ff 2f e1  |............../.|
    000080e0  dc 0e 9f e5 04 00 2d e5  04 00 9a e4 00 10 90 e5  |......-.........|
    000080f0  11 ff 2f e1 c0 0e 9f e5  04 00 2d e5 04 00 9a e4  |../.......-.....|


## FORTH Definitions

Each dialect of FORTH has its own definitions.
Development in FORTH involves extending the vocabulary with words specific to your application.
Most pre-defined words follow tradtional standards and conventions, but see the tables below for details.

### Built-in FORTH Variables

Variables are words that place an address on the stack.
Use `@` (fetch) and `!` (store) to read/write the current value of a variable.
The following variables are pre-defined in _pijFORTHos_

| Variable | Description |
|----------|-------------|
| `STATE` | Is the interpreter executing code (0), or compiling a word (non-zero)? |
| `HERE` | Address of the next free byte of memory.  When compiling, compiled words go here. |
| `LATEST` | Address of the latest (most recently defined) word in the dictionary. |
| `S0` | Address of the top of the parameter/data stack. |
| `BASE` | The current base for printing and reading numbers. (initially 10). |

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
| `FALSE` | Boolean predicate False (0) |
| `TRUE` | Boolean predicate True (1), anything != 0 is TRUE |

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
| `1+` | ( n -- n+1 ) | increment the top element |
| `1-` | ( n -- n-1 ) | decrement the top element |
| `4+` | ( n -- n+4 ) | increment by 4 the top element |
| `4-` | ( n -- n-4 ) | decrement by 4 the top element |
| `+` | ( n m -- n+m ) | addition |
| `-` | ( n m -- n-m ) | subtraction |
| `*` | ( n m -- n*m ) | multiplication |
| `/` | ( n m -- n/m ) | division |
| `MOD` | ( n m -- n%m ) | modulus |
| `NEGATE` | ( n -- -n ) | negation |
| `=` | ( n m -- p ) | where p is 1 when (n == m), 0 otherwise |
| `<>` | ( n m -- p ) | where p = (n <> m) |
| `<` | ( n m -- p ) | where p = (n < m) |
| `>` | ( n m -- p ) | where p = (n > m) |
| `<=` | ( n m -- p ) | where p = (n <= m) |
| `>=` | ( n m -- p ) | where p = (n >= m) |
| `0=` | ( n -- p ) | where p = (n == 0) |
| `0<>` | ( n -- p ) | where p = (n <> 0) |
| `0<` | ( n -- p ) | where p = (n < 0) |
| `0>` | ( n -- p ) | where p = (n > 0) |
| `0<=` | ( n -- p ) | where p = (n <= 0) |
| `0>=` | ( n -- p ) | where p = (n >= 0) |
| `NOT` | ( p -- !p ) | Boolean predicate not |
| `AND` | ( a b -- a&amp;b ) | bitwise and |
| `OR` | ( a b -- a&#124;b ) | bitwise or |
| `XOR` | ( a b -- a^b ) | bitwise xor |
| `INVERT` | ( a -- ~a ) | bitwise not |
| `LIT word` | ( -- ) | compile literal in FORTH word |
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
| `KEY` | ( -- c ) | read a character from input |
| `EMIT` | ( c -- ) | write character c to output |
| `CR` | ( -- ) | print newline |
| `SPACE` | ( -- ) | print space |
| `WORD` | ( -- addr len ) | read next word from input |
| `NUMBER` | ( addr len -- n e ) | convert string to number n, with e unparsed characters |
| `FIND` | ( addr len -- entry &#124; 0 ) | search dictionary for entry matching string |
| `>CFA` | ( entry -- xt ) | get code field address from dictionary entry |
| `>DFA` | ( entry -- addr ) | get data field address from dictionary entry |
| `CREATE` | ( addr len -- ) | create a new dictionary entry |
| `,` | ( n -- ) | write the top element from the stack at HERE |
| `[` | ( -- ) | change interpreter state to Immediate mode |
| `]` | ( -- ) | change interpreter state to Compilation mode |
| `: name` | ( -- ) | define (compile) a new FORTH word |
| `;` | ( -- ) | end FORTH word definition |
| `IMMEDIATE` | ( -- ) | set IMMEDIATE flag of last defined word |
| `HIDDEN` | ( entry -- ) | set HIDDEN flag of a word |
| `HIDE word` | ( -- ) | hide definition of following word |
| `' word` | ( -- xt ) | find CFA of following word (compile only) |
| `BRANCH offset` | ( -- ) | change FIP by following offset |
| `0BRANCH offset` | ( p -- ) | branch if the top of the stack is zero |
| `LITS addr len` | ( -- ) | compile literal string in FORTH word |
| `TELL` | ( addr len -- ) | write a string to output |
| `.` | ( n -- ) | print signed number and a trailing space |
| `U.` | ( u -- ) | print unsigned number and a trailing space |
| `.R` | ( n width -- ) | print signed number, padded to width |
| `U.R` | ( u width -- ) | print unsigned number, padded to width |
| `?` | ( addr -- ) | fetch and print signed number at addr |
| `DEPTH` | ( -- n ) | the number of items on the stack |
| `.S` | ( -- ) | print the contents of the stack (non-destructive) |
| `/MOD` | ( n m -- r q ) | where n = q * m + r |
| `S/MOD` | ( n m -- r q ) | alternative signed /MOD using Euclidean division |
| `QUIT` | ( -- ) | the first word to be executed, runs REPL |
| `CHAR word` | ( -- c ) | ASCII code from first character of following word |
| `DECIMAL` | ( -- ) | set number conversion BASE to 10 |
| `HEX` | ( -- ) | set number conversion BASE to 16 |
| `10# value` | ( -- n ) | interpret decimal literal value w/o changing BASE |
| `16# value` | ( -- n ) | interpret hexadecimal literal value w/o changing BASE |
| `UPLOAD` | ( -- addr len ) | XMODEM file upload to memory image |
| `DUMP` | ( addr len -- ) | pretty-printed memory dump |
| `BOOT` | ( addr len -- ) | boot from memory image (see UPLOAD) |
| `MONITOR` | ( -- ) | enter bootstrap monitor |
| `EXECUTE` | ( xt -- ) | call procedure indicated by CFA |

## FORTH-in-FORTH

Many standard words can be defined using the built-in primitives shown above.
The file `jonesforth.f` contains important and useful definitions.
It also serves as a significant corpus of example FORTH code.
The entire contents of this file can simply be copy-and-pasted
into the terminal session connected to the _pijFORTHos_ console.
Code at the end of the file displays a welcome message when processing is complete.

### Additional Constants Defined in FORTH

The following constants are defined in `jonesforth.f`

| Constant | Description |
|----------|-------------|
| `'\n'` | newline character (10) |
| `BL` | blank character (32) |
| `':'` | colon character (58) |
| `';'` | semicolon character (59) |
| `'('` | left parenthesis character (40) |
| `')'` | right parenthesis character (41) |
| `'"'` | double-quote character (34) |
| `'A'` | capital A character (65) |
| `'0'` | digit zero character (48) |
| `'-'` | hyphen/minus character (45) |
| `'.'` | period character (46) |

### Additional Words Defined in FORTH

The following words are defined in `jonesforth.f`

| Word | Stack | Description |
|------|-------|-------------|
| `LITERAL` | (C: value --) (S: -- value) | compile `LIT value` |
| `[COMPILE] word` | ( -- ) | compile otherwise IMMEDIATE word |
| `RECURSE` | ( -- ) | compile recursive call to current word |
| `p IF true-part THEN` | ( p -- ) | conditional execution |
| `p IF true-part ELSE false-part THEN` | ( p -- ) | conditional execution |
| `BEGIN loop-part p UNTIL` | ( -- ) | post-test loop |
| `BEGIN loop-part AGAIN` | ( -- ) | infinite loop (until EXIT) |
| `BEGIN p WHILE loop-part REPEAT` | ( -- ) | pre-test loop |
| `p UNLESS false-part ...` | ( p -- ) | same as `p NOT IF` |
| `( comment text ) ` | ( -- ) | comment inside definition |
| `NIP` | ( x y -- y ) | `SWAP DROP` |
| `TUCK` | ( x y -- y x y ) | `SWAP OVER` |
| `PICK` | ( x_n ... x_0 n -- x_n ... x_0 x_n ) | DUP n-th stack item |
| `SPACES` | ( n -- ) | print n spaces |
| `# value` | ( b -- n ) | interpret base-b literal value w/o changing BASE |
| `WITHIN` | ( a b c -- p ) | where p = ((a >= b) && (a < c)) |
| `ALIGNED` | ( addr -- addr' ) | round addr up to next 4-byte boundary |
| `ALIGN` | ( -- ) | align the HERE pointer |
| `C,` | ( c -- ) | write a byte from the stack at HERE |
| `S" string"` | ( -- addr len ) | create a string value |
| `." string"` | ( -- ) | print string |
| `CONSTANT name` | ( value -- ) | create named constant value |
| `ALLOT` | ( n -- addr ) | allocate n bytes of user memory |
| `CELLS` | ( n -- m ) | number of bytes for n cells |
| `VARIABLE name` | ( -- addr ) | create named variable location |
| `VALUE name` | ( n -- ) | create named value initialized to n |
| `TO name` | ( n -- ) | set named value to n |
| `+TO name` | ( d -- ) | add d to named value |
| `ID.` | ( entry -- ) | print word/name associated with dictionary entry |
| `?HIDDEN` | ( entry -- p ) | get HIDDEN flag from dictionary entry |
| `?IMMEDIATE` | ( entry -- p ) | get IMMEDIATE flag from dictionary entry |
| `WORDS` | ( -- ) | print all the words defined in the dictionary |
| `FORGET name` | ( -- ) | reset dictionary prior to definition of name |
| `CASE cases... default ENDCASE` | ( value -- ) | select case based on value |
| `test OF case-body ENDOF` | ( p -- ) | execute case-body if test non-zero |
| `CFA>` | ( xt -- 0 &#124; entry ) | `CFA>` is the opposite of `>CFA` |
| `SEE word` | ( -- ) | print source code for word |
| `:NONAME` | ( -- xt ) | define (compile) an unnamed new FORTH word |
| `['] name` | ( -- xt ) | compile `LIT` |
| `CATCH` | ( xt -- 0 &#124; n ) | execute procedure reporting n THROW or 0 |
| `THROW` | ( n -- ) | send exception n to CATCH |
| `ABORT` | ( -- ) | THROW exception -1 |
| `PRINT-STACK-TRACE` | ( -- ) | walk up return stack printing values |
| `UNUSED` | ( -- n ) | calculate number of cells remaining in user memory |

## Memory Organization

~~~
0x00000000  +----------------+
0x00001000  |                |
0x00002000  |                |
0x00003000  |                |
0x00004000  |                |
0x00005000  |                |
0x00006000  |                |
0x00007000  | s t a c k   ^  |
0x00008000  +----------------+
0x00009000  |                |
0x0000A000  | k e r n e l    |
0x0000B000  |                |
0x0000C000  |                |
0x0000D000  |                |
0x0000E000  |                |
0x0000F000  |                |
0x00010000  +----------------+
0x00011000  |                |
0x00012000  | u p l o a d    |
0x00013000  |                |
0x00014000  | b u f f e r    |
0x00015000  |                |
0x00016000  |                |
0x00017000  |                |
0x00018000  +----------------+
~~~

### Bootloader

The bootloader has two main components.
An XMODEM file transfer routine
and automatic kernel relocation code.
The relocation code allows a new kernel image
to be uploaded at a different address
than where it is expected to finally run.

On the RPi, the kernel wants to execute starting at 0x00008000.
We can't upload to that address, of course,
because that's where the **current** kernel is running!
Instead, we upload to a buffer at 0x00010000
and start running the new kernel at that address.
The first bit of code executed is position independent.
It checks where it's running,
and if it's not at 0x00008000 it copies itself there.
When the relocation code finishes,
it re-boots itself by jumping to the place
where it was just copied.
This time, it will find that it's running at the right address
and can proceed normally to the kernel entry point.

In order for this scheme to work,
we have to ensure two things.
First, the kernel image must by smaller than (32k - 256) bytes,
to fit between 0x00008000 and 0x10000000.
Second, each kernel image must begin with this automatic-relocation code:
~~~
@ _start is the bootstrap entry point
        .text
        .align 2
        .global _start
_start:
        sub     r1, pc, #8      @ Where are we?
        mov     sp, r1          @ Bootstrap stack immediately before _start
        ldr     lr, =halt       @ Halt on "return"
        ldr     r0, =0x8000     @ Absolute address of kernel memory
        cmp     r0, r1          @ Are we loaded where we expect to be?
        beq     k_start         @ Then, jump to kernel entry-point
        mov     lr, r0          @ Otherwise, relocate ourselves
        ldr     r2, =0x7F00     @ Copy (32k - 256) bytes
1:      ldmia   r1!, {r3-r10}   @ Read 8 words
        stmia   r0!, {r3-r10}   @ Write 8 words
        subs    r2, #32         @ Decrement len
        bgt     1b              @ More to copy?
        bx      lr              @ Jump to bootstrap entry-point
halt:
        b       halt            @ Full stop
~~~

From FORTH you can UPLOAD a new kernel image and BOOT it.

    UPLOAD   \ initiate XMODEM file transfer
    BOOT     \ jump to upload buffer address
