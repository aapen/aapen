= ToDo for the Forth Interpreter

== Forth repl seems to be doing way more updates than needed.

In looking at the screen updates from the REPL, it looks like we are doing
way more updating of the current line and the next line than we really need to.

== Build word that can grok a Zig function signature and create a new forty word from it.

The goal is to eliminate the need for most shims like this:

```
fn fillInteropShim(fb: u64, left: u64, top: u64, right: u64, bottom: u64, color: u64) void {
    const self: *Self = @ptrFromInt(fb);
    const c: u8 = @truncate(color);
    self.fill(left, top, right, bottom, c);
}
```

We should be able to say something like `createWordFrom(FrameBuffer.fill)` and
get a word that will pop six u64s off the stack, do the conversions, call `.fill`
and push some kind of result (if any) onto the stack.

== Forth level execption handling

Right now an unexpected exception blows the forth repl back to the boot repl.
Add factility for handling exceptions at the forth level.

Also I doubt we are handling the call_stack correctly in the case of a reset. Right now
we just empty it.

Possible API:

```
'foo 'foo-error-handler try
```

Or

```
try foo catch error-handler 
```

Or

```
{{ foo bar baz }} {{ handle-error }} try
```

Where:
```
{{ ( -- pushes the group marker onto the stack )


Did initial implementation of `'word 'handler try`. But still needs work:
* Short of doing a soft reset, there is no currently way to handle the errors in a sane fashion.
* Stack remains as it was when the error occurs.
* No access to the error in the handler.

== Fix the problems with the stacktrace word.

For some reason we are getting duplicate entries when we print the stack out, but
the execution seems fine. Example:

```
: foo stacktrace ;
OK
: bar foo ;
OK
: baz hello hello bar ;
OK
baz
Hello world!
Hello world!
[0]: repl (forty.memory.Header@2ab0c8) Offset 0
[1]: repl (forty.memory.Header@2ab0c8) Offset 8
[2]: handle-one (forty.memory.Header@2ab068) Offset 4
[3]: exec (forty.memory.Header@2a6d90) Offset 0
[4]: newline-handler (forty.memory.Header@2aa348) Offset 0
[5]: eval-command (forty.memory.Header@2a6e00) Offset 0
[6]: baz (forty.memory.Header@2ad0b8) Offset 0
[7]: baz (forty.memory.Header@2ad0b8) Offset 4
[8]: bar (forty.memory.Header@2ad068) Offset 2
[9]: stacktrace (forty.memory.Header@2a7928) Offset 0
OK
```
Note that 6-8 don't make sense. In reality `baz` called `bar` which called `foo`.== [Done but buggy] Stack trace for Forth.

With the new op code based inner() we how have a stack of Header pointers
that we can use to generate the current Forth word call stack.

Currently leaves out the words triggered from exec and eval.

== [Done] Extend the opcode to the most common and basic forth words.

Can we gain some performance by having a StackDup instruction and using
it instead of calling the wordDup function? Eliminate one function call.

Added opcodes for dup drop and swap. Also made the dup, drop and swap words
immediate. They compile the right instructions in compile mode and just
do the thing in immediate mode.

== [Done] Fix the names of the stacks.

Right now we have an rstack which is used by loops and an istack which is used
by the inner interpreter. These names don't really make a lot of sense. 
rstack should be the return stack for the interpreter and istack (as in `i` commonly
used as an loop counter) for loops.

== [Done] Command history

Add `history` (prints command history) and `history-add` (adds to command history) words
and integrate them into the forth repl.


