noecho
base @ decimal

( FRAME BUFFER )

: physical-size                   rot 0x 48003 2-2tag ;
: virtual-size                    rot 0x 48004 2-2tag ;
: depth                          swap 0x 48005 1-1tag ;
: overscan                            0x 4800a 4-4tag ;
: allocate-framebuffer 16 swap 0 swap 0x 40001 2-2tag ;
: fb-pitch                     0 swap 0x 40008 1-1tag ;

( a -- a' )
: set-palette
  0x    4800b w!+
    34 values w!+                         ( 32 palette entries + offset + length )
    34 values w!+
            0 w!+                         ( offset 0 )
           32 w!+                         ( length 32 )
  0x 00000000 w!+                         ( RGB of entry 0 )
  0x 00ffffff w!+
  0x 000000ff w!+
  0x 00eeffaa w!+
  0x 00cc44cc w!+
  0x 0055cc00 w!+
  0x 00e44140 w!+
  0x 0077eeee w!+
  0x 005588dd w!+
  0x 00004466 w!+
  0x 007777ff w!+
  0x 00333333 w!+
  0x 00777777 w!+
  0x 0066ffaa w!+
  0x 00f3afaf w!+
  0x 00bbbbbb w!+                         ( RGB of entry 15 )
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+
  0x 00ffffff w!+                         ( RGB of entry 31 )
  walign
;

variable fb
variable fbsize
variable fbpitch
variable fbxres
variable fbyres

: initialize-fb
  tags{{
    768 1024 physical-size
    768 1024 virtual-size
    8 depth
    0 swap 0 swap 0 swap 0 swap overscan
    allocate-framebuffer
    fb-pitch
    set-palette
  }}

  ( these are sensitive to the order of the tags )
  26 msg[] w@ 0x 3fffffff and fb !
  27 msg[] w@ fbsize !
  31 msg[] w@ fbpitch !
   6 msg[] w@ fbyres !
   5 msg[] w@ fbxres !
;

( x y -- a )
: pixel fbpitch @ * + fb @ + ;

initialize-fb
3    0   0 pixel c!
4 1023   0 pixel c!
5 1023 767 pixel c!
6    0 767 pixel c!

echo
base !
