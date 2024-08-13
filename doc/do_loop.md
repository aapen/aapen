# Notes on implementation of DO..LOOP and friends

## Implementation choices

Compiling DO and friends requires a control-flow stack. We will follow the lead of existing flow-control words from `jonesforth.f` and use the parameter stack for the control flow stack.

It would probably be faster to implement this with a register mapping for the innermost loop count and limit. However that would create a bifurcation in the control flow words that would be confusing, since we would need an assembly implementation. And if we're going to move any of the control flow words  into assembly then we should probably move all of them.

DO..LOOP is a bit like while..repeat, but with the test compiled in before the repeat.

From `jonesforth.f` comments on while..repeat:

```
\ begin condition while loop-part repeat
\	-- compiles to: --> condition 0branch offset2 loop-part branch offset
\	where offset points back to condition (the beginning) and offset2 points to after the whole piece of code
\ So this is like a while (condition) { loop-part } loop in the C language
: while immediate
	' 0branch ,	\ compile 0branch
	here @		\ save location of the offset2 on the stack
	0 ,		\ compile a dummy offset2
;

: repeat immediate
	' branch ,	\ compile branch
	swap		\ get the original offset (from begin)
	here @ - ,	\ and compile it after branch
	dup
	here @ swap -	\ calculate the offset2
	swap !		\ and back-fill it in the original location
;
```

Here's a sketch of how `do` could operate.

1. Mark `immediate`.
2. Compile words to put TOS (count) and TOS- (limit) onto rstack. `i` and `j` can reach into known offsets from RSP get the count
3. Save `here` on dstack (like begin)

Then we have the loop body.

At the end of the body we have `loop`. It should have the effect of `1 +loop`.

For the operation of `+loop`:

1. Mark `immediate`.
2. Compile a word to increment the loop count
3. Compile a word to test the limit
4. Use `0branch` to conditionally jump back to the start of the body. Compute the offset using the location that `do` saved on the dstack.
5. If the branch wasn't taken, we're done. Compile 2 rdrops to restore the rstack.

`unloop` is just 2 `rdrop`s.

I don't know how to implement `leave` in a reasonable way. It seems to require more bookkeeping and backpatching than I want to deal with right now.

I'm going to defer `?do` until I need it.

### +loop with negative index

The [standard][STD-+LOOP] has this vexing phrase: "If the loop index did not cross the boundary between the loop limit minus one and the loop limit, continue execution". Obviously this is a mathematically precise way to handle both positive and negative indexes, and limits that are either greater than or less than the starting index. How do we translate it into high level forth?

An ARM32 assembly implementation that I found looks like this: 

```
  movs r0, #0x80
  lsls r0, #24 @ #0x80 --> #0x80 000000  6*4=24 Stellen schieben.
  adds r0, rloopindex
  adds rloopindex, tos
  subs r0, rlooplimit
  adds r0, tos  @ Flags are set here, Overflow means: Terminate loop.
  drop
  bx lr
```

where `rloopindex` is `r4` and `rlooplimit` is `r5`. This implementation doesn't use the return stack for the loop control.

The first two instructions load r0 with -2^31. When adding rloopindex, there are two cases depending on whether the index is negative or positive:

```
+----------------+-----------------------------+-------+
| index < 0      | r0 is large positive number | V = 0 |
| index > 0      | r0 is large negative number | V = 1 |
+----------------+-----------------------------+-------+
```

`TOS` holds the step to apply. It gets added to rloopindex regardless of whether we continue the loop or not. Then the loop limit is subtracted from r0. I think we now have 4 cases:

```
+------------+---------------+---------------------------------------------+-------+
| index < 0  | limit > index | r0 is a large negative number               | V = 1 |
| index < 0  | limit < index | r0 is a slightly less large positive number | V = 0 |
| index > 0  | limit > index | r0 is a large positive number               | V = 1 |
| index > 0  | limit < index | r0 is a slightly less large negative number | V = 0 |
+------------+---------------+---------------------------------------------+-------+
```

So r0 now holds `INT_MIN + index - limit`

All that was setup. Even though the code uses `adds` and `subs`, I'm not sure the overflow flag has any practical effect up until this point.

Now the `TOS` is added to `r0` yielding `INT_MIN + index - limit + step`. But the sequence--not the formula--is the key. If this last addition causes r0 to cross from `INT_MIN` to `INT_MAX` or vice versa (i.e. wrap around from negative to positive or positive to negative) then we have "crossed the boundary between the loop limit minus one and the loop limit" and should terminate the loop.

Let's try some cases. (Some of these probably have off-by-one errors in the wraparound from `INT_MIN` to `INT_MAX`.)

| index | limit | step | r0                                        | V_final |
|-------|-------|------|-------------------------------------------|---------|
| 4     | 5     | 1    | `INT_MIN` + 4 - 5 + 1 = `INT_MIN`         | 1       |
| 10    | 100   | 1    | `INT_MIN` + 10 - 100 + 1 = `INT_MAX` - 88 | 0       |
| 1     | 0     | -1   | `INT_MIN` + 1 - 0 + -1 = `INT_MIN`        | 0       |
| 0     | 0     | -1   | `INT_MIN` + 0 - 0 + -1 = `INT_MAX`        | 1       |
| 5     | 0     | -10  | `INT_MIN` + 5 - 0 + -10 = `INT_MAX` - 5   | 1       |

How to implement this in high level words?

## Excerpts from the [standard][STD]

### [Control-flow stack][STD-CONTROLFLOWSTACK]

The control-flow stack is a last-in, first out list whose elements define the permissible matchings of control-flow words and the restrictions imposed on data-stack usage during the compilation of control structures.

The elements of the control-flow stack are system-compilation data types.

The control-flow stack may, but need not, physically exist in an implementation. If it does exist, it may be, but need not be, implemented using the data stack. The format of the control-flow stack is implementation defined.

### [DO][STD-DO]

#### Compilation

( C: -- do-sys )

Place do-sys onto the control-flow stack. Append the run-time semantics given below to the current definition. The semantics are incomplete until resolved by a consumer of do-sys such as [LOOP] [STD-LOOP].

#### Execution

( n1 | u1 n2 | u2 -- ) ( R: -- loop-sys )

Set up loop control parameters with index n2 | u2 and limit n1 | u1. An ambiguous condition exists if n1 | u1 and n2 | u2 are not both the same type. Anything already on the return stack becomes unavailable until the loop-control parameters are discarded.

### [?DO][STD-?DO]

#### Compilation

( C: -- do-sys )

Put do-sys onto the control-flow stack. Append the run-time semantics given below to the current definition. The semantics are incomplete until resolved by a consumer of do-sys such as [LOOP][STD-LOOP].

#### Execution

( n1 | u1 n2 | u2 -- ) ( R: -- loop-sys )

If n1 | u1 is equal to n2 | u2, continue execution at the location given by the consumer of do-sys. Otherwise set up loop control parameters with index n2 | u2 and limit n1 | u1 and continue executing immediately following [?DO][STD-?DO]. Anything already on the return stack becomes unavailable until the loop control parameters are discarded. An ambiguous condition exists if n1 | u1 and n2 | u2 are not both of the same type.

### [I][STD-I]

#### Execution

( -- n | u ) ( R: loop-sys -- loop-sys )

n | u is a copy of the current (innermost) loop index. An ambiguous condition exists if the loop control parameters are unavailable.

### [J][STD-J]

#### Execution

( -- n | u ) ( R: loop-sys1 loop-sys2 -- loop-sys1 loop-sys2 )

n | u is a copy of the next-outer loop index. An ambiguous condition exists if the loop control parameters of the next-outer loop, loop-sys1, are unavailable.

### [LOOP][STD-LOOP]

#### Compilation

( C: do-sys -- )

Append the run-time semantics given below to the current definition. Resolve the destination of all unresolved occurrences of [LEAVE][STD-LEAVE] between the location given by do-sys and the next location for a transfer of control, to execute the words following the [LOOP][STD-LOOP].

#### Execution

( -- ) ( R: loop-sys1 -- | loop-sys2 )

An ambiguous condition exists if the loop control parameters are unavailable. Add one to the loop index. If the loop index is then equal to the loop limit, discard the loop parameters and continue execution immediately following the loop. Otherwise continue execution at the beginning of the loop.

### [+LOOP][STD-+LOOP]

#### Execution

( n -- ) ( R: loop-sys1 -- | loop-sys2 )

An ambiguous condition exists if the loop control parameters are unavailable. Add n to the loop index. If the loop index did not cross the boundary between the loop limit minus one and the loop limit, continue execution at the beginning of the loop. Otherwise, discard the current loop control parameters and continue execution immediately following the loop.

### [LEAVE][STD-LEAVE]

#### Execution

( -- ) ( R: loop-sys -- )

Discard the current loop control parameters. An ambiguous condition exists if they are unavailable. Continue execution immediately following the innermost syntactically enclosing [DO][STD-DO]...[LOOP][STD-LOOP] or [DO][STD-DO]...[+LOOP][STD-+LOOP].

### [UNLOOP][STD-UNLOOP]

### Execution

( -- ) ( R: loop-sys -- )

Discard the loop-control parameters for the current nesting level. An UNLOOP is required for each nesting level before the definition may be EXITed. An ambiguous condition exists if the loop-control parameters are unavailable.

### Example

``` forth
: X ...
   limit first DO
   ... test IF ... UNLOOP EXIT THEN ...
   LOOP ...
;
```

## References

[STD]: https://forth-standard.org/standard/core
[STD-CONTROLFLOWSTACK]: https://forth-standard.org/standard/usage#usage:controlstack
[STD-DO]: https://forth-standard.org/standard/core/DO
[STD-?DO]: https://forth-standard.org/standard/core/qDO
[STD-I]: https://forth-standard.org/standard/core/I
[STD-J]: https://forth-standard.org/standard/core/J
[STD-LOOP]: https://forth-standard.org/standard/core/LOOP
[STD-LEAVE]: https://forth-standard.org/standard/core/LEAVE
[STD-+LOOP]: https://forth-standard.org/standard/core/PlusLOOP
[STD-UNLOOP]: https://forth-standard.org/standard/core/UNLOOP
