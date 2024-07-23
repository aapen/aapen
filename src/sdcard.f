noecho
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

peripherals 0x   300000 + constant emmc-base
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
emmc-base   0x       fc + constant emmc-slotisr-ver

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

variable block-size

( todo: there has to be a better way to make an array variable )
4 cells allot constant last-response

( fn pin -- )
: gpio-fsel
  10 /mod                       ( fn inreg reg# -- )
  ."     pin: " .s
  4 * gpio-fsel0 +              ( fn inreg regaddr )
  -rot                          ( reg fn inreg )
  3 * lshift                    ( reg fn mask )
  ." reg val: " .s
  swap w!
;

( cmd -- cmd idx )
: cmd-index dup 24 rshift 0x f and ;
: cmd-response-type dup 16 rshift 3 and ;
: cmd-is-data? dup 21 rshift 1 and ;

( true if upper 8 bits are > 32 )
( cmd -- cmd b )
: app-command? cmd-index 32 < ;

( n_arg n_cmd -- b )
: issue-app-command
  2drop 0
;

( n_arg n_cmd -- b )
: issue-normal-command
  block-size @ emmc-blksz w!
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

: emmc-reset
  0 block-size !

  ( reset host )
  cmd-reset-host emmc-control1 w!

  ( wait for control register bits to be cleared )
  ( todo: timeout )
  begin emmc-control1 w@ cmd-reset-all and while repeat

  ( set up clock )
  clock-emmc clock-rate

  ( set clock freq )
  emmc-control1 w@
  1 or  ( set clock int enable bit )
  ( todo get clock divider and or it in )
  0x f 16 lshift invert and  ( mask some bits ?? )
  11 16 lshift or ( set bit some bits )
  emmc-control1 w!

  ( wait for clock stable bit to be set )
  ( todo: timeout )
  begin emmc-control1 w@ dup . 2 and 0= while repeat

  ( enable clock )
  30 delay
  0 emmc-control1 w@ 4 or emmc-control1 w!
  30 delay

  ( disable interrupts )
  0 emmc-int-ena w!
  0 invert emmc-int-flags w!
  0 invert emmc-int-mask w!
  10 delay

  cmd-go-idle emmc-send-command if ." go idle failed " then




;

: emmc-read ;

: emmc-enable
  0 34 gpio-fsel 0 35 gpio-fsel 0 36 gpio-fsel 0 37 gpio-fsel 0 38 gpio-fsel
  0 39 gpio-fsel

  7 48 gpio-fsel 7 49 gpio-fsel 7 50 gpio-fsel 7 51 gpio-fsel 7 52 gpio-fsel

  emmc-reset if ." reset failed " then
;

: emmc-report-version
  emmc-slotisr-ver w@
  ( look at word from offset 0xfe )
  0x 10 rshift
  ." Vendor version: "
  dup 8 rshift 0x ff and . cr
  ." SD host specification version: "
  0x ff and case
    0 of ." 1.00 " endof
    1 of ." 2.00 " endof
    2 of ." 3.00 " endof
    ." not recognized " .
  endcase
  cr
;

." stack before restoring base " .s cr

base !
echo
