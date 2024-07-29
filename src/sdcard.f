( noecho )
base @ decimal

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

( see SD Specifications Part A2 SD Host Controller Simplified Specification Version 3.00 )
peripherals 0x   300000 + constant emmc-base
emmc-base   0x        0 + constant emmc-arg2
emmc-base   0x        4 + constant emmc-blksz
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
emmc-base   0x       30 + constant emmc-int-flags
emmc-base   0x       34 + constant emmc-int-mask
emmc-base   0x       38 + constant emmc-int-ena
emmc-base   0x       3c + constant emmc-control2
emmc-base   0x       40 + constant emmc-capabilities
emmc-base   0x       fc + constant emmc-slotisr-ver

1 32 lshift 1- constant ~0

: clear-all! 0 swap w! ;
: set-all!  ~0 swap w! ;

( nbits shift v -- (v>>shift)&((1<<bits+1)-1) )
: bits> swap rshift 1 rot lshift 1- and ;

( v shift f -- v|v<<shift )
: >bits lshift or ;

( nbits shift v -- v & ~(1<<nbits)-1 )
: 0bits
  swap rot 1 swap lshift 1-
  swap lshift invert and
;

( Make a command word from its constituent parts )
( idx ct isd ie ce rt rb mb dir ac bc ra -- word )
: emmc-command
  ( compute word )
  0
  swap 24 lshift or ( idx )
  swap 22 lshift or ( ct )
  swap 21 lshift or ( isd )
  swap 20 lshift or ( ie )
  swap 19 lshift or ( ce )
  swap 16 lshift or ( rt )
  swap  6 lshift or ( rb )
  swap  5 lshift or ( mb )
  swap  4 lshift or ( dir )
  swap  2 lshift or ( ac )
  swap  1 lshift or ( bc )
                 or ( ra )
  ( read next word make a constant )
  constant
;

0  0  0  0  0  0  0  0  0  0  0   0 emmc-command cmd-go-idle
0  0  0  0  0  0  0  0  0  0  0   1 emmc-command cmd-reset-host
0  0  0  0  0  0  0  0  0  0  0   2 emmc-command cmd-reset-cmd
0  0  0  0  0  0  1  1  0  0  0   2 emmc-command cmd-send-cide
0  0  0  0  0  0  2  1  0  0  0   3 emmc-command cmd-send-relative-addr
0  0  0  0  0  0  0  0  0  0  0   4 emmc-command cmd-reset-data
0  0  0  0  0  0  1  0  0  0  0   5 emmc-command cmd-io-set-op-cond
0  0  0  0  0  0  3  1  0  0  0   7 emmc-command cmd-select-card
0  0  0  0  0  0  0  0  0  0  0   7 emmc-command cmd-reset-all
0  0  0  0  0  0  2  1  0  0  0   8 emmc-command cmd-send-if-cond
0  0  0  0  0  0  2  1  0  0  0  16 emmc-command cmd-set-block-len
0  0  0  1  0  0  2  1  0  1  0  17 emmc-command cmd-read-block
0  1  1  1  1  0  2  1  0  1  0  18 emmc-command cmd-read-multiple
0  0  0  0  0  0  2  0  0  0  0  41 emmc-command cmd-ocr-check
0  0  0  1  0  0  2  1  0  1  0  51 emmc-command cmd-send-scr
0  0  0  0  0  0  2  1  0  0  0  55 emmc-command cmd-app
1  1  3  1  1 15  3  1  1  1  3  24 emmc-command cmd-write-block
1  1  3  1  1 15  3  1  1  1  3  25 emmc-command cmd-write-multiple

: cmd-response-type dup 16 rshift 3 and ;
: cmd-is-data?      dup 21 rshift 1 and ;
: cmd-index         dup 24 rshift 0x f and ;
: app-command?      cmd-index 32 < ;

variable block-size

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

400000 constant target-clock-rate

: clock-divisor
(  target-clock-rate
  clk-emmc clock-rate stash           ( ask HW for base freq )
  <=
  if
  else
  then
)
  target-clock-rate ( stub return value )
;

( n_arg n_cmd -- b )
: issue-app-command
  2drop 0
;

( n_arg n_cmd -- b )
: issue-normal-command
  block-size @ emmc-blksz w!    ( this needs to be done on every command? )
  swap emmc-arg1 w!
  dup emmc-cmdtm w!
  10 delay

  ( look for 0x8001 in interrupt flags )
  ( todo: timeout )
  begin emmc-int-flags w@ 0x 8001 and while ." + " 10 delay repeat

  ( read, then clear interrupt flags )
  emmc-int-flags w@ 0x ffff0001 emmc-int-flags w!

  last-response
  emmc-resp0 w@ swap ! 4+
  emmc-resp1 w@ swap ! 4+
  emmc-resp2 w@ swap ! 4+
  emmc-resp3 w@ swap ! 4+

  ( todo: if command is data, do data transfer )
  ( todo: if command is data or repsonse-type is R48busy? do some weird wait for register stuff )

  ( claim it succeeded )
  2drop 1
;

( n_arg n_cmd -- b )
: emmc-send-command app-command? if issue-app-command else issue-normal-command then ;

: emmc-reset-host
  ( reset host )
  cmd-reset-host emmc-control1 w!

  ( wait for control register bits to be cleared )
  200 cmd-reset-all emmc-control1 await-clear if ." reset timeout" cr 1 exit then

  0
;

: emmc-setup-clock
  ( get clock & reset control )
  emmc-control1 w@

  ( clock divisor in bits 8..15 )
  4 16 rot 0bits                        ( clear timeout control register )
  8 24 rot 0bits                        ( clear reset register )
  8  8 rot 0bits                        ( clear clock divisor )

  8 0 clock-divisor stash bits>         ( stash divisor, get lower 8 bits )
  8 swap >bits                          ( put lower 8 bits of divisor in register bits 8..15)

  2 8 unstash bits>                     ( unstash divisor, get upper 2 )
  6 swap >bits                          ( put lower 2 bits of divisor in register bits 6..7 )

  0 1 >bits                             ( set internal clock enable )
  emmc-control1 w!

  ( wait for clock stable bit to be set )
  begin 1 2 emmc-control1 w@ bits> 0= while repeat

  ( enable clock )
  30 delay
  emmc-control1 w@
  2 1 >bits
  emmc-control1 w!
  30 delay

  0
;

: emmc-disable-interrupts
  emmc-int-ena   clear-all!
  emmc-int-flags set-all!
  emmc-int-mask  set-all!
  10 delay
;

: emmc-reset
  0 block-size !
  emmc-reset-host               if ." reset host failed" cr 1 exit then
  emmc-setup-clock              if ." setup clock failed" cr 1 exit then
  emmc-disable-interrupts
  cmd-go-idle emmc-send-command if ." go idle failed" cr 1 exit then
;

: emmc-enable
  0 34 gpio-fsel 0 35 gpio-fsel 0 36 gpio-fsel 0 37 gpio-fsel 0 38 gpio-fsel
  0 39 gpio-fsel

  7 48 gpio-fsel 7 49 gpio-fsel 7 50 gpio-fsel 7 51 gpio-fsel 7 52 gpio-fsel

  emmc-reset if ." reset failed " 1 exit then
;


: emmc-timeout-freq
  emmc-capabilities w@ dup
  6 0 rot bits> .
  1 7 rot bits> if ." MHz" else ." KHz" then
;

: emmc-block-length
  3 16 emmc-capabilities w@ bits>
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

  ( do a blank set_sdhost_clock, which queries the clock. test word 1 of the reply )
  ." Firmware sets cdiv? "
  ~0 ~0 0 0x 38042 tags{{ swap 3-3tag }} 5 msg[] w@ ~0 <> if ." Yes" else ." No" then
  cr
;

." stack depth at end: " depth . cr

base !
echo
