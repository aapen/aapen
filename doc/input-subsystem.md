# August 18th - Changes to the input system

## Rationale

We inherited the input system from Jonesforth, but with a crucial
difference. Jones relies on the Linux `read(2)` call to fill the input
buffer from the keyboard.

Our first cut at running Jones on bare metal Pi had `key` (we
lowercased the words for calmness) directly calling `_con_in` to read
a character from the UART. This had the effect of removing all
buffering from the input system. Therefore when `word` called `key`,
it would react immediately. As soon as you would hit enter or type a
space, `word` would see the end of the word and return it to
`interpret`. This turned the interactive experience into a high-stakes
"don't miss" game of precision typing.

We have learned that we're not _that_ precise in our typing.

Also, input echoing was done by `key`, controlled by a variable
`echo`. This also added the responsibility to `key` for cr to crnl
conversion.

Next we added the ability to take input from "files". Since we don't
have a disk system yet, these "files" are really zero-terminated
buffers that are compiled into the kernel. Extending `key` to look at
the top of an "input stack" of handlers allowed us to interpret those
buffers with minimal change to callers of `key`.

The next change was to allow backspacing. This worked by having `word`
look for a backspace character from `key`. Whenever `word` would
receive an ASCII 8, it would decrement its buffer pointer (but
stopping at zero characters in the buffer.) In order to back up a
terminal cursor `key` would _also_ look for ASCII 8 and do a little
dance by emitting a sequence `8 32 8`. That backs up the cursor,
writes a space to overwrite the previous character, then backing up
the cursor again. This worked well enough, but thanks to the
high-precision game, backspace would _visually_ look like it was
erasing an entire line but would _logically_ only operate within the
current word.

There were some advantages to this approach, despite the muddled
responsibilities. Mainly, we did not need to change the "upper" layers
of Jones that much. Since the changes were buried inside `word` and
`key`, we did not need to change the implementation of `interpret`,
`see`, `constant`, `(`, or any other parsing words.

## Desired state

When interacting at the terminal, we want line editing. That means we
can backspace across whitespace boundaries all the way back to the
start of the line. Later, we should be able to use cursor-movement
keys like "home", "end", "left arrow", and "right arrow".

We should be able to implement a screen or block editor. That means we
need use `key` freely, with full control over the action of backspace
and enter.

In the test vocabulary--and probably elsewhere--we should be able to
use the standard word `source` to display the current parse buffer.

We should be able to handle multiple input sources, including the
ability for one file to go evaluate a different file.

We should be able to handle inputs that include ASCII control
characters, allowing applications to act on them without the need to
undo low-level substitutions.

We should be able to (eventually) handle keyboard input via USB,
without the need for a totally separate set of words.

## Inspirations

The [Forth standard](https://forth-standard.org) includes some words
that deal with the layered history of Forth system I/O. These include
definitions for `source-id`, `refill`, `key`, `word`, and
`parse`. Standard `quit` uses `refill` to acquire some input for
`interpret` to operate on.

## Complications

Jones uses `key` in places where a standard Forth system would
probably use `parse`. For example, the implementation of `(` calls
`key` directly. So do `s"`, `."`, and `z"`.

Our own `d\` (debug-comment) also uses `key` to look for the end of
the line.

## Design

### Buffers
We will have an *input buffer* and a *word buffer*. 

We will define a variable `>in` per the standard. It holds the address
of a cell containing the offset in characters from the start of the
*input buffer* to the start of the *parse area*.

We will define a variable `srclen`. It holds the address of a cell
containing the number of characters in the *input buffer*.

The *parse area* is the range of memory from *input buffer* + `>in @`
to *input buffer* + `srclen @`

The new word `source` returns the address and length of the *input
buffer*.

### Sources

We will define a variable `source-id` per the standard:

* 0 - the input source is the keyboard
* -1 - the input source is a string (via `evaluate`)
* u - a positive number indicates a "file id" (this is not going to be
  implemented just yet but is reserved for future use)

We will define `save-input` and `restore-input` per the standard. They
have implementation-defined stack effects.

For `save-input`:

* When `source-id` is 0, `save-input` will push the *input-buffer*,
  `>in`, `srclen`, 0 (for the source id itself) and 4 onto the stack.
* When `source-id` is -1, `save-input` will push the buffer address,
  `>in`, `srclen`, -1, and 4 onto the stack.
* We will decide how to handle files later
  
For `restore-input`:

* Expect a 4 on top of the stack.
* Examine the next item as a potential `source-id`.
* Expect to pop and restore `srclen`, `>in`, and the buffer address.

### Refill

The new word `refill` fills the *input buffer* from the keyboard.

If the current *input source* is not the keyboard, `refill`
immediately returns false.

When `refill` fills the input buffer, it sets the contents of `srclen`
to the number of characters it provided. It will also set the contents
of `>in` to 0.

### Word

Today `word` calls `key`. We will redefine `word` to examine the
*input-buffer*, returning the address and length of the next word it
finds. "Next word" means the following:

1. Start from *input-buffer* + `>in @`
2. Skip all blanks.
3. Starting with the first non-blank character, copy characters to
   *word-buffer* until one of the following is observed:
   1. A blank.
   2. EOL
   3. *input-buffer* is exhausted
4. Update `>in` to reflect how much of *input-buffer* was consumed
5. Return the address and length of the word in *word-buffer* on the
   stack.
6. Zero length means no word was observed.

Either the interpreter or an application can call `word` repeatedly to
walk through the contents of the *input-buffer*.

### Parsing

The *input buffer* will be used by `word` and `parse`. These will copy
characters without modification from the *input buffer* to the *word
buffer*. `interpret` will exclusively use the *word buffer*.

It is the job of `word` and `parse` to update `>in`. However, a
program may also modify `>in`. A program _should_ ensure that it does
not set `>in` to be outside the range `[0, srclen)`.

We will change `key` to return a terminal or keyboard input without
modification and without acting on the key.

Parsing words such as `s"` and `(` will no longer use `key`. Instead,
they will use `parse` to look for a delimited range.

### Evaluating buffers

The non-standard `readbuf` will be replaced by `evaluate` per the
standard. It will update the *input source* to -1, the *input buffer*
to the start of the buffer. It will also set `srclen` to the length of
the buffer and `>in` to 0. (Note that this means `source tell` would
print the _entire_ buffer.)

The current "input stack" mechanic will be taken over by
`evaluate`. It will save the current *input specification* using
`save-input` before it starts interpreting the buffer. When the *parse
area* is empty, `evaluate` will restore the previous *input
specification* using `restore-input`.

The current constants in armforth.S that hold the raw address of the
embedded files will be changed into words that put the address _and
length_ on the stack. So these files will be treated as strings
instead of zstrings. That way they can be used with `evaluate`. As an
example, `assembler readbuf` will be replaced with `assembler
evaluate`.

### Serial

To make terminal interaction easier, we will simplify `_con_in` and
`_con_out` to only interface with the UART hardware. A new function
`_con_readline` will provide the "cooked" input buffer. When
`source-id` is 0, `refill` will use `_con_readline` to acquire a
fully-edited line of input. Thus `_con_readline` is where we will
eventually supply cursor movement behavior.

### Other changes

Some other primary and secondary words need to be changed:

* `(` - currently loops calling `key` and counting nested parens. Will
  be replaced with a call to `parse` and use the semantic in the
  standard. This means we will lose the ability to have nested
  parens. It's going to have an annoying ripple effect on
  jonesforth.f.
* `s"` - currently loops calling `key` until the closing dquote is
  seen. Will be updated to use `parse` to find the closing dquote,
  then copy the (transient) string returned by `parse` into either the
  current word being compiled (if in compiling state) or temporary
  space above `here` if interpreting.
* `."` - if compiling, currently injects `s"`, then the string, then a
  call to tell, into the current word. This should work without
  further change, since `s"` will be updated. If interpreting, `."`
  currently loops calling `key` until the closing dquote is seen. This
  usage will be updated to use `parse` to find the closing dquote,
  then call `tell` to print the string.
* `z"` - behaves like `s"` but adds a null to the end of the
  string. Can be updated in the same way as `s"`
* `d\` - loops on `key` until `\n` is seen. Will be updated to use
  parse to locate the EOL

### Not Addressed

There are some other parts of input handling in the Forth standard
that we need to think about but don't need to deal with right
now. Those mainly revolve around files and parsing from files. Here is
a list of words that we are explicitly not implementing now:

* `included`
* `include-file`
* `include`
* `require`
* `required`
* `blk`
* `block`
* `buffer`
* `empty-buffers`
* `load`
* `save-buffers`

### Current status

August 18, 2024

While implementing the new input semantics, I've added `word2` and
`interpret2` to work as described above. This is mostly working now,
although I haven't yet factored backspace handling into
`_con_readline` as described. I'm reaching a point where I will have
to change `:` to use the new `word` function. However once I do that,
a lot of `jonesforth.f` will break since `s"` and `(` still try to
read via `key`. I'm trying to find a way to make the next step less of
a big breaking leap. Hence this design document, which has helped me
clarify some of the steps to take.
