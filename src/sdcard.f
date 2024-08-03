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
: use-rca     1 32 >bits ;
: delay-100   1 33 >bits ;
: delay-1000  2 33 >bits ;

39 cells allot constant sdcommands
: cmd[]       cells sdcommands + ;
: cmd.code    cmd[] @ 0x  ffffffff and ;
: cmd.rca?    cmd[] @ 0x 100000000 and 0<> ;
: cmd.delay   cmd[] @ 33 rshift 0x 3 and ;
: cmd.isdata? cmd[] @ 0x    200000 and 0<> ;
: cmd.rtype   cmd[] @ 16 rshift 0x 3 and ;
: cmd.app?    32 >= ;

: mkcmd dup cmd[] ! constant ;

39 cells 0x 00 sdcommands memset
( cmd.code is CMD number from SD card spec )
( cmd-* constants are defined as the index in our array )
( cmd-* constants are never sent to the device )
 0 cmd                                                0 mkcmd cmd-go-idle
 2 cmd resp-136                                       1 mkcmd cmd-all-send-cid
 3 cmd resp-48                                        2 mkcmd cmd-send-rel-addr
 4 cmd                                                3 mkcmd cmd-set-dsr
 6 cmd resp-48                                        4 mkcmd cmd-switch-func
 7 cmd resp-48b use-rca                               5 mkcmd cmd-card-select
 8 cmd resp-48b delay-100                             6 mkcmd cmd-send-if-cond
 9 cmd resp-136 use-rca                               7 mkcmd cmd-send-csd
10 cmd resp-136 use-rca                               8 mkcmd cmd-send-cid
11 cmd resp-48                                        9 mkcmd cmd-volt-switch
12 cmd resp-48b                                      10 mkcmd cmd-stop-xfer
13 cmd resp-48  use-rca                              11 mkcmd cmd-send-status
15 cmd          use-rca                              12 mkcmd cmd-go-inactive
16 cmd resp-48b                                      13 mkcmd cmd-set-blocklen
17 cmd resp-48  is-data from-card                    14 mkcmd cmd-read-single
18 cmd resp-48  is-data from-card multiblock counted 15 mkcmd cmd-read-multi
19 cmd resp-48                                       16 mkcmd cmd-send-tuning
20 cmd resp-48b                                      17 mkcmd cmd-speed-class
23 cmd resp-48                                       18 mkcmd cmd-set-blockcnt
24 cmd resp-48  is-data                              19 mkcmd cmd-write-single
25 cmd resp-48  is-data multiblock counted           20 mkcmd cmd-write-multi
27 cmd resp-48                                       21 mkcmd cmd-program-csd
28 cmd resp-48b                                      22 mkcmd cmd-set-write-pr
29 cmd resp-48b                                      23 mkcmd cmd-clr-write-pr
30 cmd resp-48                                       24 mkcmd cmd-snd-write-pr
32 cmd resp-48                                       25 mkcmd cmd-erase-wr-st
33 cmd resp-48                                       26 mkcmd cmd-erase-wr-end
38 cmd resp-48b                                      27 mkcmd cmd-erase
42 cmd resp-48                                       28 mkcmd cmd-lock-unlock
55 cmd                                               29 mkcmd cmd-app
55 cmd resp-48  use-rca                              30 mkcmd cmd-app-rca
56 cmd resp-48                                       31 mkcmd cmd-gen-cmd
 6 cmd resp-48                                       32 mkcmd cmd-set-bus-width
14 cmd resp-48  use-rca                              33 mkcmd cmd-sd-status
22 cmd resp-48                                       34 mkcmd cmd-send-num-wrbl
23 cmd resp-48                                       35 mkcmd cmd-send-num-ers
41 cmd resp-48  delay-1000                           36 mkcmd cmd-app-send-op-cond
42 cmd resp-48                                       37 mkcmd cmd-set-clr-det
51 cmd resp-48  is-data from-card                    38 mkcmd cmd-send-scr

variable block-size

1 constant etout
2 constant eirpt

( n -- n-1 or throws )
: tout? dup 0<= if ." throwing etout" cr etout throw then 1- ;

( tries mask addr -- )
: await-clear
  ." await clear"
  begin
    dup w@ 2 pick               ( tries mask addr val mask )
    and 0<>                     ( tries mask addr notclear )
  while
    rot tout? -rot
  repeat
  drop drop drop
;

( todo: duplication between await-clear and await-set )
( tries mask addr -- )
: await-set
  ." await set"
  begin
    dup w@ 2 pick
    and 0=
  while
    rot tout? -rot
  repeat
  drop drop drop
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

( tries -- )
: wait-for-command
  ." wait-for-command"
  begin
    emmc-status    w@ 0x 01 and            ( cmd inhibit bit )
    emmc-interrupt w@ 0x 17f8000 and not   ( any error interrupt )
    and
  while
    tout?
  repeat
  drop
;

: clear-interrupts emmc-interrupt w@ emmc-interrupt w! ;

( tries irpt -- b )
: await-interrupt
  ." await-interrupt" cr
  begin
    dup emmc-interrupt w@ and 0=
  while
    swap tout? swap
  repeat
  2drop

  ." irpt observed" cr

  emmc-interrupt w@
  dup 0x   10000 and 0<> if emmc-interrupt w! etout throw then
  dup 0x  100000 and 0<> if emmc-interrupt w! etout throw then
  dup 0x 17f8000 and 0<> if emmc-interrupt w! eirpt throw then
  drop
  emmc-interrupt w!                     ( write mask back to clear our interrupt )
;

( cmd arg -- )
: issue-normal-command
  ." normal command " cr
  2drop
;

( cmd arg -- )
: emmc-send-command
  ( todo: check if app command )
  ( issue-normal-command )

  ( todo: check if RCA required, send with RCA )

  25 wait-for-command

  ." ready to send" cr

  clear-interrupts
  emmc-arg1 w!
  dup cmd.code
  emmc-cmdtm w!

  25 0x 1 ( cmd_done ) await-interrupt

  ." command complete" cr

  ( todo: handle response types )
  cmd.rtype case
    0 of ." no resp" 0 endof
    1 of ." TODO: resp-136" 0 endof
    2 of ." TODO: resp-48" 0 endof
    3 of ." TODO: resp-48 with busy" 0 endof
  endcase
;

: emmc-reset-host
  ." emmc-reset-host"
  0 emmc-control0 w!
  0 emmc-control1 w!
  1 24 lshift emmc-control1 w! ( reset host circuit )

  1 delay

  200 1 24 lshift emmc-control1 await-clear

  ( enable internal clock and set data timeout )
  0x e 16 lshift emmc-control1 w! ( data timeout unit )
  0x 1           emmc-control1 w! ( clock enable internal )

  1 delay
;

( freq -- divisor )
: get-clock-divisor
  dup 41666667 + 1- swap /              ( 41666667 + freq - 1 / freq )
  dup 0x 3ff > if drop 0x 3ff then
  dup 3 < if drop 4 then
;

( freq -- succ? )
: emmc-set-clock
  200 0x 03 emmc-status await-clear

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

  200 0b 0010 emmc-control1 await-set
;

: emmc-enable-interrupts
  emmc-irpt-en   set-all!
  emmc-irpt-mask set-all!
  10 delay
;

400000 constant clock-freq-setup

: CMD0
  cmd-go-idle 0 ['] emmc-send-command catch
  ?dup if ." CMD0 failed: " dup . cr throw then
;

: emmc-reset
  0 block-size !
  emmc-reset-host
  clock-freq-setup emmc-set-clock
  emmc-enable-interrupts
  CMD0
;

: emmc-enable
  0 34 gpio-fsel 0 35 gpio-fsel 0 36 gpio-fsel 0 37 gpio-fsel 0 38 gpio-fsel
  0 39 gpio-fsel

  7 48 gpio-fsel 7 49 gpio-fsel 7 50 gpio-fsel 7 51 gpio-fsel 7 52 gpio-fsel

  ['] emmc-reset catch ?dup if ." reset failed: " . cr then
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

sd-old-base base ! hide sd-old-base
echo
