( noecho )
base @ value sd-old-base
decimal

peripherals 0x   200000 + constant gpio-base
gpio-base   0x        0 + constant gpio-fsel0
gpio-base   0x        4 + constant gpio-fsel1
gpio-base   0x        8 + constant gpio-fsel2
gpio-base   0x        c + constant gpio-fsel3
gpio-base   0x       10 + constant gpio-fsel4
gpio-base   0x       14 + constant gpio-fsel5
gpio-base   0x       1c + constant gpio-set0
gpio-base   0x       20 + constant gpio-set1
gpio-base   0x       28 + constant gpio-clr0
gpio-base   0x       2c + constant gpio-clr1
gpio-base   0x       34 + constant gpio-lev0
gpio-base   0x       38 + constant gpio-lev1
gpio-base   0x       40 + constant gpio-eds0
gpio-base   0x       44 + constant gpio-eds1
gpio-base   0x       4c + constant gpio-ren0
gpio-base   0x       50 + constant gpio-ren1
gpio-base   0x       58 + constant gpio-fen0
gpio-base   0x       5c + constant gpio-fen1
gpio-base   0x       64 + constant gpio-hen0
gpio-base   0x       68 + constant gpio-hen1
gpio-base   0x       70 + constant gpio-len0
gpio-base   0x       74 + constant gpio-len1
gpio-base   0x       7c + constant gpio-paren0
gpio-base   0x       80 + constant gpio-paren1
gpio-base   0x       88 + constant gpio-afen0
gpio-base   0x       8c + constant gpio-afen1
gpio-base   0x       94 + constant gpio-pud
gpio-base   0x       98 + constant gpio-pudclk0
gpio-base   0x       9c + constant gpio-pudclk1

peripherals 0x   300000 + constant emmc-base
emmc-base   0x        0 + constant emmc-arg2
emmc-base   0x        4 + constant emmc-blksizecnt
emmc-base   0x        8 + constant emmc-arg1
emmc-base   0x        c + constant emmc-cmdtm
emmc-base   0x       10 + constant emmc-resp0
emmc-base   0x       14 + constant emmc-resp1
emmc-base   0x       18 + constant emmc-resp2
emmc-base   0x       1c + constant emmc-resp3
emmc-base   0x       20 + constant emmc-data
emmc-base   0x       24 + constant emmc-status
emmc-base   0x       28 + constant emmc-control0
emmc-base   0x       2c + constant emmc-control1
emmc-base   0x       30 + constant emmc-interrupt
emmc-base   0x       34 + constant emmc-irpt-mask
emmc-base   0x       38 + constant emmc-irpt-en
emmc-base   0x       3c + constant emmc-control2
emmc-base   0x       88 + constant emmc-tune-step
emmc-base   0x       fc + constant emmc-slotisr-ver

1 32 lshift 1- constant ~0

: clear-all! 0 swap w! ;
: set-all!  ~0 swap w! ;

( nbits shift v -- (v>>shift)&((1<<bits+1)-1) )
: bits> swap rshift 1 rot lshift 1- and ;

( v f shift -- v|f<<shift )
: >bits lshift or ;

( nbits shift v -- v & ~(1<<nbits)-1 )
: 0bits
  swap rot 1 swap lshift 1-
  swap lshift invert and
;

( nbits shift a -- )
: clear-bits! dup -rot w@ 0bits swap w! ;

: cmd          24 lshift ;
: is-data     1 21 >bits ;
: multiblock  1  5 >bits ;
: resp-48     2 16 >bits ;
: resp-136    1 16 >bits ;
: resp-48b    3 16 >bits ;
: from-card   1  4 >bits ;
: counted     1  1 >bits ;

 0 cmd                                              constant cmd-go-idle
 1 cmd                                              constant cmd-reset-host
 2 cmd resp-136                                     constant cmd-all-send-cid
 3 cmd resp-48                                      constant cmd-send-rel-addr
 4 cmd                                              constant cmd-set-dsr
 7 cmd resp-48b                                     constant cmd-card-select
 8 cmd resp-48b                                     constant cmd-send-if-cond
16 cmd resp-48b                                     constant cmd-set-blocklen
17 cmd resp-48 is-data from-card                    constant cmd-read-single
18 cmd resp-48 is-data from-card multiblock counted constant cmd-read-multi
24 cmd resp-48 is-data                              constant cmd-write-single
25 cmd resp-48 is-data multiblock counted           constant cmd-write-multi
55 cmd                                              constant cmd-app
55 cmd resp-48                                      constant cmd-app-rca

: response-type 16 rshift 3 and ;

variable block-size

( s -- )
: d   tell cr ;
: err tell cr 1 ;

( tries mask addr -- b )
: await-clear
  begin
    dup w@ 2 pick               ( tries mask addr val mask )
    and 0=                      ( tries mask addr clear? )
    if
      drop 2drop 0 exit         ( success )
    then
    rot 1- dup >r -rot r> 0=    ( tries-1 mask addr done? )
  until
  drop 2drop 1                  ( timed-out )
;

( todo: duplication between await-clear and await-set )
( tries mask addr -- b )
: await-set
  begin
    dup w@ 2 pick
    and 0<>
    if
      drop 2drop 0 exit
    then
    rot 1- dup >r -rot r> 0=
  until
  drop 2drop 1
;

( todo: there has to be a better way to make an array variable )
4 cells allot constant last-response

( fn pin -- )
: gpio-fsel
  10 /mod                       ( fn inreg reg# -- )
  4 * gpio-fsel0 +              ( fn inreg regaddr )
  -rot                          ( reg fn inreg )
  3 * lshift                    ( reg fn mask )
  swap w!
;

( tries -- b )
: wait-for-command
  s" wait-for-command" d
  begin
    emmc-status    w@ 0x 01 and            ( cmd inhibit bit )
    emmc-interrupt w@ 0x 17f8000 and not   ( any error interrupt )
    and
  while
    dup 0<= if s" command timeout" err exit then
    1-
  repeat
  drop
  0
;

: clear-interrupts emmc-interrupt w@ emmc-interrupt w! ;

( tries irpt -- b )
: await-interrupt
  s" await-interrupt" d
  begin
    dup emmc-interrupt w@ and 0=
  while
    swap
    dup 0<= if s" await irpt timeout" err exit then
    1-
    swap
  repeat

  emmc-interrupt w@
  dup 0x   10000 and 0<> if     emmc-interrupt w! s" cmd timeout"  err exit then
  dup 0x  100000 and 0<> if     emmc-interrupt w! s" data timeout" err exit then
  dup 0x 17f8000 and 0<> if dup emmc-interrupt w! . cr s" error"   err exit then
  drop
  emmc-interrupt w!                     ( write mask back to clear our interrupt )
  0
;

( cmd arg -- b )
: issue-normal-command
  s" normal command " d
  2drop 1
;

( cmd arg -- b )
: emmc-send-command
  ( todo: check if app command )
  ( issue-normal-command )

  ( todo: check if RCA required, send with RCA )

  25 wait-for-command if 2drop s" wait for command aborted" err exit then

  s" ready to send" d

  clear-interrupts
  emmc-arg1 w!
  dup
  emmc-cmdtm w!

  25 0x 1 ( cmd_done ) await-interrupt if drop s" timeout " err exit then

  ( todo: handle response types )
  response-type case
    0 of 0 endof
    1 of ." TODO: resp-136" 0 endof
    2 of ." TODO: resp-48" 0 endof
    3 of ." TODO: resp-48 with busy" 0 endof
  endcase
;

: emmc-reset-host
  0 emmc-control0 w!
  0 emmc-control1 w!
  1 24 lshift emmc-control1 w! ( reset host circuit )

  1 delay

  200 1 24 lshift emmc-control1 await-clear if s" reset time out" err exit then

  ( enable internal clock and set data timeout )
  0x e 16 lshift emmc-control1 w! ( data timeout unit )
  0x 1           emmc-control1 w! ( clock enable internal )

  1 delay

  0
;

( freq -- divisor )
: get-clock-divisor
  dup 41666667 + 1- swap /              ( 41666667 + freq - 1 / freq )
  dup 0x 3ff > if drop 0x 3ff then
  dup 3 < if drop 4 then
  ." divisor: " dup . cr
;

( freq -- succ? )
: emmc-set-clock
  200 0x 03 emmc-status await-clear if emmc-status w@ . s" inhibit flags timeout: " err exit then

  1 2 emmc-control1 clear-bits!   ( disable clock )
  1 delay

  get-clock-divisor               ( 10 bit clock divisor )
  dup  0x 0ff and 8 lshift        ( lower 8 bits of divisor go in control bits 8..15 )
  swap 0x 300 and 2 rshift        ( high 2 bits of divisor go in control bits 6..7 )
  emmc-control1 w@                ( read control1 )
  0x ffff001f and                 ( clear any old divisor bits )
  or or                           ( set new divisor bits )
  emmc-control1 w!                ( write it back )

  1 delay

  emmc-control1 w@ 0b 0100 or emmc-control1 w! ( set clk_en bit )

  200 0b 0010 emmc-control1 await-set if s" clock stable timeout" err exit then

  0
;

: emmc-enable-interrupts
  emmc-irpt-en   set-all!
  emmc-irpt-mask set-all!
  10 delay
;

400000 constant clock-freq-setup

: emmc-reset
  0 block-size !
  emmc-reset-host                   if s" reset host failed" err exit then
  clock-freq-setup emmc-set-clock   if s" set clock failed"  err exit then
  emmc-enable-interrupts
  cmd-go-idle 0 emmc-send-command   if s" go idle failed"    err exit then
;

: emmc-enable
  0 34 gpio-fsel 0 35 gpio-fsel 0 36 gpio-fsel 0 37 gpio-fsel 0 38 gpio-fsel
  0 39 gpio-fsel

  7 48 gpio-fsel 7 49 gpio-fsel 7 50 gpio-fsel 7 51 gpio-fsel 7 52 gpio-fsel

  emmc-reset if s" reset failed " err exit else 0 then
;

: firmware-sets-cdiv?
  ( do a blank set_sdhost_clock, which queries the clock. test word 1 of the reply )
  ~0 ~0 0 0x 38042 tags{{ swap 3-3tag }} 5 msg[] w@ ~0 <>
;

: emmc-device-probe
  cr
  emmc-slotisr-ver w@ dup
  ." Vendor version: " 8 24 rot bits> . cr
  ." SD host specification version: " 8 16 rot bits> case
    0 of ." 1.00 - NOT SUPPORTED" endof
    1 of ." 2.00 - NOT SUPPORTED" endof
    2 of ." 3.00 " endof
    ." not recognized " .
  endcase
  cr
  ." Core clock rate: " clk-emmc clock-rate . cr
  ." Firmware sets cdiv? " firmware-sets-cdiv? if ." Yes" else ." No" then cr
;

sd-old-base base !
echo
