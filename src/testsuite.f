\ test cases drawn from https://forth-standard.org
\
\ exercise these with `testsuite evaluate`

hex

.\ F.3		Basic assumptions
t{ -> }t \ test the test harness
t{ : bitsset? if 0 0 else 0 then ; -> }t \ test if any bits are set, answer in base 1
t{ 0 bitsset? -> 0 }t                    \ zero is all bits clear
t{ 1 bitsset? -> 0 0 }t                  \ other numbers have at least one bit
t{ -1 bitsset? -> 0 0 }t

.\ F.3.2		Booleans

t{ 0 0 and -> 0 }t
t{ 0 1 and -> 0 }t
t{ 1 0 and -> 0 }t
t{ 1 1 and -> 1 }t

t{ 0 invert 1 and -> 1 }t
t{ 1 invert 1 and -> 0 }t

0        constant 0s
0 invert constant 1s

t{ 0s invert -> 1s }t
t{ 1s invert -> 0s }t

t{ 0s 0s and -> 0s }t
t{ 0s 1s and -> 0s }t
t{ 1s 0s and -> 0s }t
t{ 1s 1s and -> 1s }t

t{ 0s 0s or -> 0s }t
t{ 0s 1s or -> 1s }t
t{ 1s 0s or -> 1s }t
t{ 1s 1s or -> 1s }t

t{ 0s 0s xor -> 0s }t
t{ 0s 1s xor -> 1s }t
t{ 1s 0s xor -> 1s }t
t{ 1s 1s xor -> 0s }t

.\ F.3.3		Shifts
1s 1 rshift invert constant msb
t{ msb bitsset? -> 0 0 }t

.\ F.6.1.0320	2*
t{   0s 2*       ->   0s }t
t{    1 2*       ->    2 }t
t{ 4000 2*       -> 8000 }t
t{   1s 2* 1 xor ->   1s }t
t{  msb 2*       ->   0s }t

.\ F.6.1.0330	2/
t{          0s 2/ ->   0s }t
t{           1 2/ ->    0 }t
t{        4000 2/ -> 2000 }t
\ t{          1s 2/ ->   1s }t
t{    1s 1 xor 2/ ->   1s }t
t{ msb 2/ msb and ->  msb }t

.\ F.6.1.1805	lshift
t{   1 0 lshift       ->    1 }t
t{   1 1 lshift       ->    2 }t
t{   1 2 lshift       ->    4 }t
t{   1 f lshift       -> 8000 }t
t{  1s 1 lshift 1 xor ->   1s }t
t{ msb 1 lshift       ->    0 }t

.\ F.6.1.2162	rshift
t{ 1 0    rshift         -> 1 }t
t{ 1 1    rshift         -> 0 }t
t{ 2 1    rshift         -> 1 }t
t{ 4 2    rshift         -> 1 }t
t{ 8000 f rshift         -> 1 }t
t{ msb 1  rshift msb and -> 0 }t      \ rshift zero fills msbs
t{ msb 1  rshift 2*      -> msb }t

.\ F.3.5		Comparisons
0 invert constant max-uint
0 invert 1 rshift constant max-int
0 invert 1 rshift invert constant min-int
0 invert 1 rshift constant mid-uint
0 invert 1 rshift invert constant mid-uint+1

0s constant <false>
1s constant <true>

.\ F.6.1.0270	0=
t{        0 0= -> <true>  }t
t{        1 0= -> <false> }t
t{        2 0= -> <false> }t
t{       -1 0= -> <false> }t
t{ max-uint 0= -> <false> }t
t{  min-int 0= -> <false> }t
t{  max-int 0= -> <false> }t

.\ F.6.1.0530	=
t{  0  0 = -> <true>  }t
t{  1  1 = -> <true>  }t
t{ -1 -1 = -> <true>  }t
t{  1  0 = -> <false> }t
t{ -1  0 = -> <false> }t
t{  0  1 = -> <false> }t
t{  0 -1 = -> <false> }t

.\ 6.1.0850	>r
t{ : gr1 >r r> ; -> }t
t{ : gr2 >r rsp@ @ r> drop ; -> }t
t{ 123 gr1 -> 123 }t
t{ 123 gr2 -> 123 }t
t{  1s gr1 -> 1s }t

.\ 6.1.0950	constant
t{ 123 constant x123 -> }t
t{ x123 -> 123 }t
t{ : equ constant ; -> }t
t{ x123 equ y123 -> }t
t{ y123 -> 123 }t

.\ 6.1.0750	base
: gn2 base @ >r hex base @ decimal base @ r> base ! ;
t{ gn2 -> 10 a }t

.\ 6.1.0690	abs
t{  0 abs -> 0 }t
t{  1 abs -> 1 }t
t{ -1 abs -> 1 }t

.\ 6.1.2165	s-quote
t{ : gc4 s" XY" ; -> }t
t{ gc4 swap drop -> 2 }t
t{ gc4 drop dup c@ swap char+ c@ -> 58 59 }t
: gc5 s" A string"2drop ; \ there is no space between the " and 2drop
t{ gc5 -> }t

cr
