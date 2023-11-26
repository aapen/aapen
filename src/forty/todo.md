= ToDo for the Forth Interpreter

== [Done but buggy] Stack trace for Forth.

With the new op code based inner() we how have a stack of Header pointers
that we can use to generate the current Forth word call stack.

Currently leaves out the words triggered from exec and eval.

== [Done] Extend the opcode to the most common and basic forth words.

Can we gain some performance by having a StackDup instruction and using
it instead of calling the wordDup function? Eliminate one function call.

Added opcodes for dup drop and swap. Also made the dup, drop and swap words
immediate. They compile the right instructions in compile mode and just
do the thing in immediate mode.

== Fix the names of the stacks.

Right now we have an rstack which is used by loops and an istack which is used
by the inner interpreter. These names don't really make a lot of sense. 
rstack should be the return stack for the interpreter and istack (as in `i` commonly
used as an look counter) for loops.

== Forth level execption handling

Right now an unexpected exception blows the forth repl back to the boot repl.
Add factility for handling exceptions at the forth level.

Also I doubt we are handling the call_stack correctly in the case of a reset. Right now
we just empty it.
