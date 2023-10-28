# Forty

## Syntax

  In general, the Forty syntax follows Forth syntax, except:

  * `"foo bar"` is a *seven* character string along the lines of C or Python. Double quoted strings are a special syntactical case in Forty, so you don't need a space after the initial `"`.

  * `:foo` is a three character string. The colon form of strings is useful when using words like `create` that take a string name. Note you cannot have a space in a colon defined string.
  * `'foo` is the address of the word foo.
  * \x is a single character, the integer value of the character. In this case, 120.
  * 0xnnn... is a number expressed in hex, no matter what the current base is. For example 0xa is decimal ten no matter what the current base is.
  * 0#nnn... is a number expressed in decimal, no matter what the current base is. For example 0#11 is decimal eleven no matter what the current base is.

## Words

### Testing and Inspection

* troff:  -- : Turn tracing off.
* tron:  -- : Turn tracing on.

* ?words:  -- :Print details of all the words.
* ?word:  -- :Print details of word.
* ???:  -- :Print dictionary words that begin with...
* ??:  -- :Print the dictionary.
* ?:  -- :Print description of word.
* ?stack:  -- :Print the stack.
* ?rstack:  -- :Print the return stack.

* word: A constant, the number of bytes in a word.

* dump: addr len -- : Dump an arbitrary area of memory

* assert:  b desc -- Print desc if b is not true

### Input and Output

* .: n -- :print tos as u64 in current obase
* p: n -- : Print the top of the stack followed by a newline
* cls:  -- :Clear the screen

* h.: n -- :print tos as u64 in decimal
* #.: n -- :print tos as u64 in decimal
* +#.: n -- :print tos as i64 in current obase
* +.: n -- :print tos as i64 in current obase


* key?:  -- n: Check for a key press
* key:  -- ch :Read a key

* set-colors: fg bg -- : Set the text colors
* set-bg: fg bg -- : Set the text fg color
* set-fg: fg bg -- : Set the text bg color

* draw-char: x y ch -- :Draw a char
* emit: ch -- :Emit a char
* cr:  -- :Emit a newline
* hello:  -- :Hello world!

* text: s x y -- : draw string at position
* line: x0 y0 x1 y1 c -- : draw line with color
* fill: l t r b c -- : fill rectangle with color
* blit: sx sy w h dx dy -- : Copy a screen rect

* scr-height: A constant
* scr-length: A constant
* scr-width: A constant

* black: A constant
* blue: A constant
* brown: A constant
* cyan: A constant
* dark-grey: A constant
* green: A constant
* grey: A constant
* light-blue: A constant
* light-green: A constant
* light-grey: A constant
* light-red: A constant
* orange: A constant
* red: A constant
* violet: A constant
* white: A constant
* yellow: A constant

### System Status and Low Level Operations

* mem-available:  -- n : Push number bytes of memory currently available
* mem-used:  -- n : Push number of bytes of memory currently used
* mem-total:  -- n : Push total number of bytes avail.
* mem-manager: -- addr : Push the address of the memory struct

* ticks:  -- n: Read clock

* *jump-if-not: Lower level word used by compiler
* *jump: Lower level word used by compiler
* *push-u64: Lower level word used by compiler
* *push-string: Lower level word used by compiler
* *jump-if-rle: Lower level word used by compiler
* *stop: The stop instruction (a constant) used by compiler

* reset:  -- : Soft reset the system

* dma: src dest len stride -- : Perform a DMA

### Eval and REPL

* eval-cmd: pStr -- <Results>
* eval: pStr -- <Results>
* read-eval:  -- <results> : read one word, evaluate it
* input-buffer:
* read-token: sb-addr --
* repl: --
* repl-buffer:
* read-command: sb-addr --
* emit-prompt:
* read-ch:  -- ch : read with echo

* dtab-set: key word-address dtab -- set handler for key to word-adress
* dtab-create: dt-name -- dtab: Create a 128 entry key dispatch table

### Strings and Characters

* sb-clear: sb-word --  : Clear this buffer
* sb-string: sb-addr -- str : Push the address of the string in the sb
* sb-append: ch sb-addr --  : Append a new char onto the buffer.
* sb-poke-char: ch sb-addr -- : Add a character at the current position.
* sb-dec-count: sb-addr -- : Increment the sb char count.
* sb-inc-count: sb-addr -- : Increment the sb char count.
* sb-create: pName -- : Create a new string buffer with the name

* dquote?: ch -- b
* digit?: ch -- b
* whitespace?: ch -- b
* newline?:
* backspace?:

* char-bs - A constant
* char-cr - A constant
* char-del - A constant
* char-nl - A constant
* char-space - A constant

* s=: s s -- b :string contents equality
* s.: s -- :print tos as a string

### Address and Memory Manipulation

* word-address: p-data -- p-word : Given a word data ptr, return word ptr
* word-data-len: pWord - n : Return the number of data bytes associated with word
* word-len: word-addr -- len

* aligned:  c-addr – a-addr  : Align the address.
* words:  n -- n : Number words -> number bytes

* set-mem: value addr len -- : Initialize a block of memory.

* wbe: A prim
* @w: addr -- : Load a 32 bit unsigned word
* !w: w addr -- : Store a 32 unsigned bit word.
* @b: addr -- b : Load a byte.
* !b: b addr -- : Store a byte.
* * be: A prim
* @: addr - w : Load a 64 bit unsigned word.
* !: w addr -- : Store a 64 bit unsigned word.


### Arithmetic

* decimal:  -- : Set the input and output bases to 10.
* hex:  -- : Set the input and output bases to 16.
* base:  n -- : Set the input and output bases.

* dec!:
* inc!:
* dec:
* inc:
* +]]:
* [[:

* \>=: n n -- n :u64 greater-than or equal test
* \>: n n -- n :u64 greater-than test
* \<=: n n -- n :u64 less-than or equal test
* \<: n n -- n :u64 less-than test
* \* and: n -- n :u64 and
* \* xor: n -- n :u64 xor
* \* or: n -- n :u64 or
* \* not: n -- n :u64 not
* =: n n -- n :u64 equality test
* %: n n -- n :u64 modulo
* /: n n -- n :u64 division
* *: n n -- n :u64 multiplication
* -: n n -- n :u64 subtraction
* +: n n -- n :u64 addition

### Words and the Dictionary

* immediate!:  f addr -- Change the immediate flag of the word at addr to f
* secondary!: addr -- Make the word a secondary


### ASCII Art

* F:  -- : Draw an ascii art F
* dot:  -- : Emit a dot
* bar:  -- : Emit a bar
* star:  -- : Emit a star

### InterOp

* invoke-0: addr --  : invoke a 0 arg void fn
* invoke-1: n addr --  : invoke a 1 arg void fn
* invoke-2: n n addr --  : invoke a 2 arg void fn
* invoke-3: n n n addr --  : invoke a 3 arg void fn
* invoke-4: n n n addr --  : invoke a 4 arg void fn
* invoke-5: n n n addr --  : invoke a 5 arg void fn
* invoke-6: n n n addr --  : invoke a 6 arg void fn
* invoke-0r: addr -- result : invoke a 0 arg fn, push return
* invoke-1r: n addr -- result : invoke a 1 arg fn, push return
* invoke-2r: n n addr -- result : invoke a 2 arg fn, push return
* invoke-3r: n n n addr -- result : invoke a 3 arg fn, push return
* invoke-4r: n n n addr -- result : invoke a 4 arg fn, push return
* invoke-5r: n n n addr -- result : invoke a 5 arg fn, push return
* invoke-6r: n n n addr -- result : invoke a 6 arg fn, push return

### Stack Manipulation

* clear: <anything> --

* over: w1 w2 -- w1 w2 w1
* rot: w1 w2 w3 -- w2 w3 w1
* drop: w --
* dup: w -- w w
* swap: w1 w2 -- w2 w1

* 2over: , w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2
* 2rot: w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2
* 2drop: w w --
* 2dup: w1 w2 -- w1 w2 w1 w2
* 2swap:  w1 w2 w3 w4 -- w3 w4 w1 w2

* ->stack:  -- n : Copies the rstack TOS onto the data stack, doesn't pop rstack
* ->rstack:  n -- : Push the data TOS onto the rstack, doen't pop stack.
* rstack-inc: Increment the TOS of the rstack.
* rdrop:  n -- : Drop the top rstack value
* drop:  n -- : Drop the top stack value


### Logic and Loops

* repeat:  n -- :repeat the body n times.
* times:   -- : End of repeat loop


* while:  -- :Compile the head of a while loop.
* do:  -- :Compile the condition part of a while loop.
* done:  -- :Compile the end of a while loop.

* if:  -- :If statement
* else:  -- :Part of if/else/endif
* endif:  -- :Part of if/else/endif

### Word definition

* ::  -- :Start a new word definition
* ;:  -- :Complete a new word definition

* let: v sAddr - :Assign a new variable

* create:  -- :Start a new definition
* ballot:  n -- :Allocate n bytes.
* allot:  n -- :Allocate n words.
* s,:  n -- :Add a string to memory.
* ,:  n -- :Allocate a word and store n in it.
* finish:  -- :Complete a new definition

* }:  -- : Turn compile mode back on
* {:  -- : Temp turn off compile mode.

## Lower Level Constants

### Board Related

* board.*len
* board.device.*len
* board.device.mac_address
* board.device.manufacturer
* board.device.serial_number
* board.device
* board.memory.*len
* board.memory.regions
* board.memory
* board.model.*len
* board.model.memory
* board.model.name
* board.model.pcb_revision
* board.model.processor
* board.model.version
* board.model
* board

### Frame Buffer and Console Related

* fb.*len
* fb.base
* fb.bg
* fb.bpp
* fb.buffer_size
* fb.dma
* fb.dma_channel
* fb.fg
* fb.pitch
* fb.range
* fb.vtable.*len
* fb.vtable.line
* fb.vtable
* fb.xres
* fb.yres
* fb

* fbcons.*len
* fbcons.fb
* fbcons.height
* fbcons.serial
* fbcons.tab_width
* fbcons.width
* fbcons.xpos
* fbcons.ypos
* fbcons

### Forth Interpreter Related

* forth.*len
* forth.allocator
* forth.arena_allocator
* forth.buffer
* forth.compiling
* forth.console
* forth.debug
* forth.drop
* forth.ibase
* forth.incRStack
* forth.input
* forth.jump
* forth.jumpIfNot
* forth.jumpIfRLE
* forth.lastWord
* forth.line_buffer
* forth.memory
* forth.newWord
* forth.obase
* forth.pushString
* forth.pushU64
* forth.rDrop
* forth.rstack
* forth.stack
* forth.temp_allocator
* forth.toDStack
* forth.toRStack
* forth.words
* forth


### Header (word) Related

* header.*len
* header.desc
* header.func
* header.immediate
* header.len
* header.name
* header.previous

* inner

### Memory Manager Related

* memory.*len
* memory.current
* memory.length
* memory.p
