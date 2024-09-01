# Forth Records

These are notes from video lectures by Ulrich Hoffman on the
[Forth2020](https://www.youtube.com/@Forth2020) Youtube channel.

These examples are all in SwiftForth. They rely on `DOES>` which we
don't have implemented (as of August 31, 2024) as well as specific
semantics of `CREATE` that do not match Jones.

## Arrays

From [Tutorial: Forth Data Structures (Arrays)](https://www.youtube.com/watch?v=lpkxVQt0_bU)

For an array with each element being 1 cell:

```

: Array ( n -- )
    CREATE CELLS ALLOT
  DOES> ( n -- addr )
    SWAP CELLS + ;

6 Array sq

16 4 sq !

```

During execution `Array` creates a new word for `sq` (the name follows
`Array` in the input stream) and reserves space for 6 cells in the
dictionary. At this point, the behavior of the newly-created `sq` word
is to push its data field address (DFA) on the stack. Next, as `Array`
executes its `DOES>` portion, `DOES>` _replaces_ the execution
semantics of the newly-created `sq` with `SWAP CELLS +`. But when
`Array` was compiled, `DOES>` also appended "initiation semantics" to
`Array`. Specifically, `Array`'s definition received initiation
semantics that put the DFA of the newly-created `sq` on the stack
_before_ invoking the (replaced by `DOES>`) execution semantics of
`sq`. (Whew... what a confusing tangle: we have to think about both
compilation and execution time of `Array` as well as compilation and
execution time of `DOES>`, while also keeping in mind the _evolving_
definition of `sq` as it gets built. As a shorthand, we can think of
`Array` as a constructor for words, with the part before `DOES>`
creating the word and `DOES>` providing the word's behavior. There's
just an invisible address push that `DOES>` provides.)

For an array with bounds checking:

```
: Array ( u -- )
    CREATE DUP , CELLS ALLOT  \ stores in memory: { u x0 ... xu-1 }
    DOES> ( i -- addr )
      2DUP @ ( i a i u )
        U< 0= -24 AND THROW   \ invalid numeric argument
        CELL+  ( i 'x0 )
        SWAP CELLS + ;
```

This reserves memory for the elements of the array plus one cell for
the number of elements size. In the reserved memory, the array size is
one cell _before_ the 0th element of the array. The unsigned compare
allows us to check against both the zero bound and the upper bound in
one comparison. The `-24 and` will result in either zero (if the index
is in range) or the standard throw code for "invalid numeric
argument". No `if` is necessary because `throw` only acts if TOS is
non-zero.

From [Tutorial: Arrays: automatic resizing, RAM/ROM](https://youtu.be/hjeyjLjj5nc?si=PB2zi32JRL5wefal&t=1345)

The previous examples stored the data directly in the parameter field
(body) of the words. It can instead by indirectly references by a
pointer in the parameter field.

```
: Array ( u -- )
  DUP 1+ CELLS HERE SWAP ALLOT
  SWAP OVER !
  CREATE ,
  DOES> ( I -- ADDR )
    @ 2DUP @ ( I A I U )
    U< 0= -24 AND THROW
    CELL+
    SWAP CELLS + ;
```

For dynamic memory, there are the Forth-2012 standard's extension
words `ALLOCATE`, `FREE`, and `RESIZE`.

```
: DOUBLE ( addr -- ) DUP @ ( size ) 2* DUP >R RESIZE THROW R> OVER ! ;

: FIT ( i array -- ) \ assure index fits in array
  BEGIN ( i a )
    2DUP @ @ U< 0=
  WHILE ( i a )
    DUP @ DOUBLE OVER !
  REPEAT ( i a )
  2DROP ;

: RESIZING-ARRAY ( u -- )
  DUP 1+ CELLS ALLOCATE THROW
  SWAP OVER !
  CREATE ,
  DOES>
      OVER 0< -24 AND THROW
      2DUP FIT
      @ CELL+
      SWAP CELLS + ;
```


## Structures / records

From [Tutorial: Forth data structures](https://www.youtube.com/watch?v=6xFYcHhjojY).

Using a defining word to make field words:

```
VARIABLE TTIME 0 ,
: cField: ( n1 <name> -- n2 )
  CREATE DUP , 1+
  DOES> ( addr1 -- addr2 ) @ + ;

0
cField: >tenths
cField: >secs
cField: >minutes
cField: >hours
DROP
```

This assumes all the fields are one byte.

Using the Forth-2012 standard word `+FIELD`:

```
VARIABLE TTIME 0 ,

: +FIELD ( n1 n2 <name> -- n3 )
  CREATE OVER , +
  DOES> ( addr1 -- addr2 ) @ + ;

0
1 +FIELD >tenths
1 +FIELD >secs
1 +FIELD >minutes
1 +FIELD >hours
DROP
```

Using `+FIELD` to define a "Point" structure

```
0
    1 CELLS +FIELD _x
    1 CELLS +FIELD _y
CONSTANT POINT

CREATE P POINT ALLOT
3 P _x ! 4 P _y !

_x @ dup * _y @ dup * + sqrt     \ distance of P from origin
```

The constant `POINT` will have the size in cells of the structure
(because +FIELD leaves that on the stack).

This does not deal with alignment requirements that some CPUs impose
on larger values. This can be done by using the word "ALIGNED" inside
the structure definition.

Ulrich says that it's quite easy to put execution tokens into fields,
thereby creating objects.

## Enumerations

From [FORTH2020 & ForthGesellschaft ZOOM15
NOV.2021](https://www.youtube.com/watch?v=CgxwbeLWSZM) segment "Ulrich
Hoffman: Tutorial: Forth Data Structures (enumeration types)".

The most basic approach -- just use constants:

```
0 CONSTANT black
1 CONSTANT red
2 CONSTANT green
3 CONSTANT yellow

: .color
  DUP black  = IF DROP ." black"  EXIT THEN
  DUP red    = IF DROP ." red"    EXIT THEN
  DUP green  = IF DROP ." green"  EXIT THEN
  DUP yellow = IF DROP ." yellow" EXIT THEN
  ." color " . ;
```

Or, let the interpreter do the calculation:

```
0
DUP CONSTANT black  1+
DUP CONSTANT red    1+
DUP CONSTANT green  1+
DUP CONSTANT yellow 1+
DROP
```

Maybe we'd prefer to express it with teh calculation in one place:

```
0
DUP 1+ SWAP CONSTANT black
DUP 1+ SWAP CONSTANT red
DUP 1+ SWAP CONSTANT green
DUP 1+ SWAP CONSTANT yellow
DROP
```

As Ulrich points out: "Attention! Repeated phrases might be a sign of bad factoring"

So, factoring out the calculation and adding a defining word:

```
: iota DUP 1+ SWAP ;
: Enum iota CONSTANT ;

0 Enum black
  Enum red
  Enum green
  Enum yellow
DROP
```

Something similar lets us name bits:

```
: iota DUP 1+ SWAP ;
: Bit iota 1 SWAP LSHIFT CONSTANT ;

0 Bit bit-zero
  Bit bit-one
  Bit bit-two
  Bit bit-three
DROP

status @ bit-two   OR         status ! \ set bit two
status @ bit-three INVERT AND status ! \ reset bit three
```

## Gaps in Jones

- Most glaring, we don't have `DOES>`. A comment from the original jonesforth.f stated that `DOES>` could not be implemented in indirect-threaded Forths.
- In SwiftForth (and standard Forth-2012) `CREATE` makes a word that pushes its DFA on the stack. Our `CREATE` makes a word that has no valid execution semantics. (`create p p` will cause a core abort.)

