# Ziggy

A simple Forth written in Zig.

Currently the following words are defined:

 *  : Define a new secondary word. 
 *  ; End secondary word definition.
 *  hello Prints "Hello world"
 *  . Pops and prints the top of the stack.
 *  stack Non destructive print of entire stack.
 *  ? Non destructive print of entire stack.
 *  rstack Non destructive print of the return stack.
 *  cr Print a newline.
 *  swap Swap the top two items on the stack. 
 *  + Add the top two items on the stack, push the result.
 *  info Print misc info.
 *  ?? Print the dictionary.
 *  ip Push the current instruction pointer onto the stack.
 *  !i (Experimental) Get an integer from the address on stack.
 *  @i (Experimental) Get the integer value at the address on the stack.
 *  value-size Push the size of a `Value`.

