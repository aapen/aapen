# Forty

A simple Forth written in Zig.

You will be greeted by a `OK>>` prompt and you can start typing Forth words:

    OK>> 10 11 + . cr
    21
    OK>>

## Value syntax

Simply entering a number:

    OK>> 42

Will push a i32 onto the stack.

You can express you numbers in hex as well:

    OK>> 0xff

A number with a decimal point will give you a an f32:

    OK>> 3.14

Strings are surrounded by double quotes.
Note that strings cannot currently contain whitespace!

    OK>> "hello"

Single `u8` characters use the backslash:

    OK>> \x
    OK>> emit

## Built In Words

Currently the following words are defined:

 *  `:` Define a new secondary word. 
 *  `;` End secondary word definition.
    `emit` Prints the value on the stack as a char. Takes ints and char values.
 *  `hello` Prints "Hello world"
 *  `.` Pops and prints the top of the stack.
 *  `h.` Pops and prints the top of the stack as a hex number.
 *  `stack` Non destructive print of entire stack.
 *  `?` Non destructive print of entire stack.
 *  `rstack` Non destructive print of the return stack.
 *  `cr` Print a newline.
 *  `+` Add the top two items on the stack, pushes the result.
 *  `+` Subtracts the top two items on the stack, pushes the result.
 *  `info` Print misc info.
 *  `??` Print the dictionary.
 *  `ip` Push the current instruction pointer onto the stack.
 *  `!i` (Experimental) Get an integer from the address on stack.
 *  `@i` (Experimental) Get the integer value at the address on the stack.
 *  `value-size` Push the size of a `Value`.
 *  `swap` Swap the top two items on the stack. 
 *  `2swap` Reverses the top two pairs of numbers.
 *  `dup` Duplicate the value on the stack.
 *  `2dup` Duplicates the top pair of numbers.
 *  `drop` Drops the top value.
 *  `2drop` Drop the top two values on the stack.
 *  `rot`  Rotate the top 2 values on the stack.
 *  `2rot`  Rotate the top three cell pairs on the stack.
 *  `over`  Grabs the 2nd item on the stack and pushes it.
 *  `2over` Duplicates the second pair of numbers.
