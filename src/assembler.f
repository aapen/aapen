noecho

( ARM assembler )

( Utility words that set fields on the instructions. )

: set-rt ( instruction rt - instruction )
  or
;

: set-rn ( instruction rn -- instruction )
  0d 5 lshift
  or
;

: set-rm ( instruction rm -- instruction )
  0d 16 lshift
  or
;

: set-im21-hi ( instruction im21 -- instruction )
  2 rshift 5 lshift             ( instruction im21-hibits )
  or
;

: set-im21-low ( instruction im21 -- instruction )
  0x 3 and 29 lshift		( instruction im21-lowbits )
  or
;

: set-im21 ( instruction im21 -- instruction )
  dup rot rot			( im21 instruction im21 )
  set-im21-hi			( im21 instruction )
  swap set-im21-low             ( instruction )
;

  
( These are the actual assembler instructions. )

: ldrimmx ( rt rn -- instruction )
  0x f9400000			( push the basic opcode )
  swap set-rn			( rt ins )
  swap set-rt			( ins )
;

: adr ( rt relative )
  0x 10000000			( rt relative base-instruction )
  swap set-im21			( rt instruction )
  swap set-rt
;

(
  Very rough poc, this word will crash, but if you xray it you will
  see the two instructions embedded inside of the definition.
)

: test1
  hello
  hello
  [
  	17 17 ldrimmx w,
	30 24 adr w,
  ]
  hello
  hello
;

echo

