### Testing and Inspection

assert:  b desc -- if b is not true 

troff:  -- : Turn tracing off.
tron:  -- : Turn tracing on.

?words:  -- :Print details all the words.
?word:  -- :Print details of word.
???:  -- :Print dictionary words that begin with...
??:  -- :Print the dictionary.
?:  -- :Print description of word.
?stack:  -- :Print the stack.
?rstack:  -- :Print the return stack.

dump: addr len -- : Dump an arbitrary area of memory

h.: n -- :print tos as u64 in decimal
#.: n -- :print tos as u64 in decimal
.: n -- :print tos as u64 in current obase
+#.: n -- :print tos as i64 in current obase
+.: n -- :print tos as i64 in current obase


### Input and Output

key?:  -- n: Check for a key press
key:  -- ch :Read a key

set-colors: fg bg -- : Set the text colors
set-bg: fg bg -- : Set the text fg color
set-fg: fg bg -- : Set the text bg color

cls:  -- :Clear the screen
draw-char: x y ch -- :Draw a char
emit: ch -- :Emit a char
cr:  -- :Emit a newline
hello:  -- :Hello world!

text: s x y -- : draw string at position
line: x0 y0 x1 y1 c -- : draw line with color
fill: l t r b c -- : fill rectangle with color
blit: sx sy w h dx dy -- : Copy a screen rect

### System Status and Low Level Operations

mem-available:  -- n : Push number bytes of memory currently available
mem-used:  -- n : Push number of bytes of memory currently used
mem-total:  -- n : Push total number of bytes avail.
mem-manager: -- addr : Push the address of the memory struct

ticks:  -- n: Read clock

*jump-if-not: A prim
*jump: A prim
*push-u64: A prim
*push-string: A prim
*jump-if-rle: A prim

eval-cmd: pStr -- <Results>
eval: pStr -- <Results>
reset:  -- : Soft reset the system

dma: src dest len stride -- : Perform a DMA
### Eval and REPL

read-eval:  -- <results> : read one word, evaluate it
input-buffer: 
read-token: sb-addr --
repl: --
repl-buffer: 
read-command: sb-addr --
emit-prompt: 
read-ch:  -- ch : read with echo

dtab-set: key word-address dtab -- set handler for key to word-adress
dtab-create: dt-name -- dtab: Create a 128 entry key dispatch table

### Strings and Characters

sb-clear: sb-word --  : Clear this buffer
sb-string: sb-addr -- str : Push the address of the string in the sb
sb-append: ch sb-addr --  : Append a new char onto the buffer.
sb-poke-char: ch sb-addr -- : Add a character at the current position.
sb-dec-count: sb-addr -- : Increment the sb char count.
sb-inc-count: sb-addr -- : Increment the sb char count.
sb-create: pName -- : Create a new string buffer with the name

dquote?: ch -- b
digit?: ch -- b
whitespace?: ch -- b
newline?: 
backspace?: 

s=: s s -- b :string contents equality
s.: s -- :print tos as a string

### Address and Memory Manipulation

word-address: p-data -- p-word : Given a word data ptr, return word ptr
word-data-len: pWord - n : Return the number of data bytes associated with word
word-len: word-addr -- len

aligned:  c-addr – a-addr  : Align the address.
words:  n -- n : Number words -> number bytes 

set-mem: value addr len -- : Initialize a block of memory.

wbe: A prim
@w: addr -- : Load a 32 bit unsigned word
!w: w addr -- : Store a 32 unsigned bit word.
@b: addr -- b : Load a byte.
!b: b addr -- : Store a byte.
be: A prim
@: addr - w : Load a 64 bit unsigned word.
!: w addr -- : Store a 64 bit unsigned word.


### Arithmetic

decimal:  -- : Set the input and output bases to 10.
hex:  -- : Set the input and output bases to 16.
base:  n -- : Set the input and output bases.

dec!: 
inc!: 
dec: 
inc: 
+]]: 
[[: 

>=: n n -- n :u64 greater-than or equal test
>: n n -- n :u64 greater-than test
<=: n n -- n :u64 less-than or equal test
<: n n -- n :u64 less-than test
and: n -- n :u64 and
xor: n -- n :u64 xor
or: n -- n :u64 or
not: n -- n :u64 not
=: n n -- n :u64 equality test
%: n n -- n :u64 modulo
/: n n -- n :u64 division
*: n n -- n :u64 multiplication
-: n n -- n :u64 subtraction
+: n n -- n :u64 addition

### Words and the Dictionary

immediate!:  f addr -- Change the immediate flag of the word at addr to f
secondary!: addr -- Make the word a secondary


### ASCII Art

p:  n -- : Print the top of the stack followed by a newline
F:  -- : Draw an ascii art F
dot:  -- : Emit a dot
bar:  -- : Emit a bar
star:  -- : Emit a star 

### InterOp

invoke-0: addr --  : invoke a 0 arg void fn
invoke-1: n addr --  : invoke a 1 arg void fn
invoke-2: n n addr --  : invoke a 2 arg void fn
invoke-3: n n n addr --  : invoke a 3 arg void fn
invoke-4: n n n addr --  : invoke a 4 arg void fn
invoke-5: n n n addr --  : invoke a 5 arg void fn
invoke-6: n n n addr --  : invoke a 6 arg void fn
invoke-0r: addr -- result : invoke a 0 arg fn, push return
invoke-1r: n addr -- result : invoke a 1 arg fn, push return
invoke-2r: n n addr -- result : invoke a 2 arg fn, push return
invoke-3r: n n n addr -- result : invoke a 3 arg fn, push return
invoke-4r: n n n addr -- result : invoke a 4 arg fn, push return
invoke-5r: n n n addr -- result : invoke a 5 arg fn, push return
invoke-6r: n n n addr -- result : invoke a 6 arg fn, push return

### Stack Manipulation

clear: <anything> --

over: w1 w2 -- w1 w2 w1
rot: w1 w2 w3 -- w2 w3 w1
drop: w --
dup: w -- w w
swap: w1 w2 -- w2 w1

2over: , w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2
2rot: w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2
2drop: w w --
2dup: w1 w2 -- w1 w2 w1 w2
2swap:  w1 w2 w3 w4 -- w3 w4 w1 w2 

->stack:  -- n : Copies the rstack TOS onto the data stack, doesn't pop rstack
->rstack:  n -- : Push the data TOS onto the rstack, doen't pop stack.
rstack-inc: Increment the TOS of the rstack.
rdrop:  n -- : Drop the top rstack value
drop:  n -- : Drop the top stack value


### Logic and Loops

repeat:  n -- :repeat the body n times.
times:   -- : End of repeat loop


while:  -- :Compile the head of a while loop.
do:  -- :Compile the condition part of a while loop.
done:  -- :Compile the end of a while loop.

if:  -- :If statement
else:  -- :Part of if/else/endif
endif:  -- :Part of if/else/endif

### Word definition

::  -- :Start a new word definition
;:  -- :Complete a new word definition

let: v sAddr - :Assign a new variable

create:  -- :Start a new definition
ballot:  n -- :Allocate n bytes.
allot:  n -- :Allocate n words.
s,:  n -- :Add a string to memory.
,:  n -- :Allocate a word and store n in it.
finish:  -- :Complete a new definition

}:  -- : Turn compile mode back on
{:  -- : Temp turn off compile mode.

