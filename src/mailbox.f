noecho

( save current base )
base @
hex

( n n -- n )
: max 2dup > if drop else nip then ;
: min 2dup < if drop else nip then ;

( n r -- n )
: round 1- invert and ;

            3f000000   constant peripherals
peripherals     b880 + constant mbox-read
mbox-read         10 + constant mbox-peek
mbox-read         18 + constant mbox-status
mbox-read         20 + constant mbox-write

( buffer we will use to send & receive from )
128 cells allot constant mailscratch

: delay ( n -- : loop n times )
  begin ?dup while 1- repeat
;

1 1e lshift constant mbox-status-empty
1 1f lshift constant mbox-status-full

: mbox-empty? mbox-status w@ mbox-status-empty and ;
: mbox-full?  mbox-status w@ mbox-status-full  and ;

: mboxflush ( -- : discard any pending messages )
  begin
    mbox-empty? not
  while
    mbox-read w@ drop
    1 delay
  repeat
;

( ch a -- a )
: send
  begin mbox-full? while repeat         ( wait for space )
  8 round                               ( clear lower 4 bits )
  or
  mbox-write w!
;

( -- a ch )
: receive
  begin mbox-empty? while repeat        ( wait for reply )
  mbox-read w@                          ( read message )
  dup f invert and                      ( mask off channel )
  swap f and                            ( extract channel )
;

( Temporary state )
variable message-start                  ( pointer to start of message buffer )

( Formatting messages )

: values 4 * ;

( a w -- a' )
: w!+ over w! 4+ ;

( align addr to next 32 bit boundary )
( a -- a )
: align32 3 + 3 invert and ;

( Start a bundle of messages )
( a -- )
: draft
  dup
  message-start !
  0 w!+                                 ( reserve space for payload size )
  0 w!+                                 ( reserve space for result status )
;

( a -- )
: finish
  0 w!+                                 ( write terminator )
  message-start @                       ( p_cur p_start)
  -                                     ( len )
  message-start @ w!                    ( write payload size )
;

( append a "Frame buffer set depth" tag )
( a n -- a' )
: depth
  swap                                  ( n a | )
   48005 w!+                          ( n a | tag id )
  1 values w!+                          ( n a | size of values sent )
  1 values w!+                          ( n a | size of values returned )
  swap     w!+                          ( a   | parameter 1 )
  align32
;

( append a "Frame buffer set size" tag )
( a yres xres virt? -- a')
: size
     48003 +                            ( a n n n  | compute tag id )
  3 pick swap w!+                       ( a n n a' | write tag id )
  2 values    w!+                       ( a n n a' | size of values sent )
  2 values    w!+                       ( a n n a' | size of values returned )
  swap        w!+                       ( a n a'   | parameter 1 )
  swap        w!+                       ( a a'     | parameter 2 )
  nip                                   ( a        |  )
  align32
;

( append a "Frame buffer set overscan" tag )
( a top bottom left right -- a' )
: overscan
   4800a
  5 pick swap w!+
  4 values    w!+
  4 values    w!+
  swap        w!+
  swap        w!+
  swap        w!+
  swap        w!+
  nip
  align32
;

: allocate-framebuffer
     40001   w!+
  2 values   w!+
  2 values   w!+
  10         w!+
  0          w!+
  align32
;

: get-fb-pitch
     40008   w!+
  1 values   w!+
  1 values   w!+
  aeaeaeae   w!+
  align32
;

( a -- a' )
: set-palette
  4800b     w!+
  22 values w!+                         ( 32 palette entries + offset + length )
  22 values w!+
         0  w!+                         ( offset 0 )
        20  w!+                         ( length 32 )
  00000000  w!+                         ( RGB of entry 0 )
  00ffffff  w!+
  000000ff  w!+
  00eeffaa  w!+
  00cc44cc  w!+
  0055cc00  w!+
  00e44140  w!+
  0077eeee  w!+
  005588dd  w!+
  00004466  w!+
  007777ff  w!+
  00333333  w!+
  00777777  w!+
  0066ffaa  w!+
  00f3afaf  w!+
  00bbbbbb  w!+                         ( RGB of entry 15 )
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+
  00000000  w!+                         ( RGB of entry 31 )
  align32
;

1 constant virtual
0 constant physical

( a -- a' )
: msg-fbinit
  draft
  300 400 physical size
  300 400 virtual size
  8 depth
  0 0 0 0 overscan
  allocate-framebuffer
  set-palette
  get-fb-pitch
  finish
;

variable fb
variable fbsize
variable pitch

: initialize-fb
  8                                     ( channel )
  mailscratch msg-fbinit                ( channel buf )
  mailscratch send                      (  )
  receive                               ( buf channel )
  drop                                  ( buf | assume its the right channel )

  ( these are sensitive to the order of tags in msg-fbinit )
  dup 68 + w@ fb !
  dup 6c + w@ fbsize !
  dup 110 + w@ pitch !
;

( x y )
: pixel pitch @ * + fb @ + ;

hide delay
hide values

( restore old base )
base !
echo

initialize-fb

3 0 0 pixel c!
4 10 10 pixel c!
