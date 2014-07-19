\ Adapted from the forth version at 
\ http://rosettacode.org/wiki/N-queens_problem
\ requires jonesforth.f

VARIABLE SOLUTIONS
VARIABLE NODES
 
: BITS ( N -- MASK ) 1 SWAP LSHIFT 1- ;
: LOWBIT  ( MASK -- BIT ) DUP NEGATE AND ;
: LOWBIT- ( MASK -- BITS ) DUP 1- AND ;

: NEXT3 ( DL DR F FILES -- DL DR F DL' DR' F' )
  INVERT >R
  2 PICK RSP@ @ AND 2* 1+
  2 PICK RSP@ @ AND 2/
  2 PICK R> AND ;
 
: TRY ( DL DR F -- )
  DUP IF
    1 NODES +!
    DUP 2OVER AND AND
    BEGIN ?DUP WHILE
      DUP >R LOWBIT NEXT3 RECURSE R> LOWBIT-
    REPEAT
  ELSE 1 SOLUTIONS +! THEN
  DROP 2DROP ;
 
: QUEENS ( N -- )
  0 SOLUTIONS ! 0 NODES !
  -1 -1 ROT BITS TRY
  SOLUTIONS @ . ." SOLUTIONS, " NODES @ . ." NODES" CR ;
 
8 QUEENS  \ 92 SOLUTIONS, 1965 NODES
