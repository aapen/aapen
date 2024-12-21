( Save the current base and set it to hex )

( ARM assembler )

( Utility words that set fields on the instructions. )
: set-rt ( instruction rt - instruction )
  or
;

: set-ra ( instruction ra -- instruction )
  0b11111 and
  0d10 lshift
  or
;

: set-rn ( instruction rn -- instruction )
  0b11111 and
  0d5 lshift
  or
;

: set-rm ( instruction rm -- instruction )
  0b11111 and
  0d16 lshift
  or
;

: set-im21-hi ( instruction im21 -- instruction )
  0d2 rshift 0d5 lshift       ( instruction im21-hibits )
  or
;

: set-im21-low ( instruction im21 -- instruction )
  0d3 and 0d29 lshift		( instruction im21-lowbits )
  or
;

: set-im26 ( instruction im26 -- instruction )
  0x3ffffff and			( instruction im26 )
  or
;

: set-im21 ( instruction im21 -- instruction )
  dup rot rot			( im21 instruction im21 )
  set-im21-hi			( im21 instruction )
  swap set-im21-low             ( instruction )
;

: set-im19 ( instruction im19 -- instruction )
  0b1111111111111111111 and	( instruction im19 )
  0d5 lshift                   ( instruction mask )
  or
;

: set-im16 ( instruction im16 -- instruction )
  0b1111111111111111 and	( instruction im16 )
  0d5 lshift                   ( instruction mask )
  or
;

: set-im12 ( instruction im12 -- instruction )
  0b111111111111 and		( instruction im12 )
  0d10 lshift                  ( instruction mask )
  or
;

: set-im9 ( instruction im9 -- instruction )
  0b111111111 and		( instruction im9 )
  0d12 lshift                  ( instruction mask )
  or
;

: set-im6 ( instruction im6 -- instruction )
  0b111111 and			( instruction im6 )
  0d10 lshift                  ( instruction mask )
  or
;

: rt-rn-rm-ra-instruction ( rt rn rm ra opcode -- instruction )
  swap set-ra			( rt rn rm instuction )
  swap set-rm			( rt rn instuction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rt-rn-rm-instruction ( rt rn rm opcode -- instruction )
  swap set-rm			( rt rn instuction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rt-rn-im9-instruction ( rt rn im9 opcode -- instruction )
  swap set-im9			( rt rn instruction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rt-rn-im12-instruction ( rt rn im12 opcode -- instruction )
  swap set-im12			( rt rn instruction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rt-rn-im19-instruction ( rt rn im19 opcode -- instruction )
  swap set-im19			( rt rn instruction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rn-instruction ( rn opcode -- instruction )
  swap set-rn			( rn instuction )
;

: rt-rn-instruction ( rt rn opcode -- instruction )
  swap set-rn			( rn instuction )
  swap set-rt			( instruction )
;

: im16-instruction ( im16 opcode -- instruction )
  swap set-im16
;

: rt-im16-instruction ( rt im16 opcode -- instruction )
  swap set-im16
  swap set-rt
;

: rt-im19-instruction ( rt im19 opcode -- instruction )
  swap set-im19			( rt instruction )
  swap set-rt
;

: rt-im21-instruction ( rt im21 opcode -- instruction )
  swap set-im21			( rt instruction )
  swap set-rt
;

( Condition codes used by the b-cond instruction )

: cond-eq 0b0000 ;
: cond-ne 0b0001 ;
: cond-cs 0b0010 ;
: cond-cc 0b0011 ;
: cond-mi 0b0100 ;
: cond-pl 0b0101 ;
: cond-vs 0b0110 ;
: cond-vc 0b0111 ;
: cond-hi 0b1000 ;
: cond-ls 0b1001 ;
: cond-ge 0b1010 ;
: cond-lt 0b1011 ;
: cond-gt 0b1100 ;
: cond-le 0b1101 ;
: cond-al 0b1110 ;
: cond-nv 0b1111 ;


( Instruction modifiers )

( Turn instruction into the 32 bit version of itself )

: ->w ( instruction -- instruction )
  0x7fffffff and	( clear bit 31 )
;

( Turn on the shift option )

: ->shift ( instruction -- instruction )
  1 0d22 lshift
  or
;

( Set the condition code for a b-cond instruction )

: ->cond ( instruction cond -- instruction )
  0b1111 and
  or
;

( Set the preindex option )

: ->pre ( instruction -- instruction )
  0b11 0d10 lshift
  or
;

( Set the postindex option )

: ->post ( instruction -- instruction )
  0b01 0d10 lshift
  or
;


( These are the actual assembler instructions. )

( Load and store )

( Note the immediate offsets are multiplied by 8 when executed )

: ldr-x[x]#  ( rt rn im12 -- instruction )  0xf8400000 rt-rn-im9-instruction ->post ;
: ldr-x[x]   ( rt rn      -- instruction )  0 0xf8400000 rt-rn-im9-instruction ;

: ldr-x[x#]! ( rt rn im12 -- instruction )  0xf8400000 rt-rn-im9-instruction ->pre ;
: ldr-x#     ( rt im19 -- instruction )     58000000 rt-im19-instruction ;

: ldrb-w[x]# ( rt rn im9 -- instruction ) 0x38400000 rt-rn-im9-instruction ->post ;
: ldrb-w[x]  ( rt rn     -- instruction ) 0 0x39400000 rt-rn-im12-instruction ;
: ldrb-w[x#] ( rt rn im12 -- instruction ) 0x39400000 rt-rn-im12-instruction ;

( TBD this has problems with neg imm values )

: ldr-x[x#]  ( rt rn im12 -- instruction )  0xf9400000 rt-rn-im12-instruction ;

: str-x[x#]! ( rt rn im12 -- instruction ) 0xf8000000 rt-rn-im9-instruction ->pre ;
: str-x[x#]  ( rt rn im12 -- instruction ) 0xf8000000 rt-rn-im9-instruction ;
: str-x[x]#  ( rt rn im12 -- instruction ) 0xf8000000 rt-rn-im9-instruction ->post ;

: strb-w[x#]  ( rt rn im12 -- instruction ) 0x39000000 rt-rn-im12-instruction ;
: strb-w[x]   ( rt rn im12 -- instruction ) 0 strb-w[x#] ;
: strb-w[x]#  ( rt rn im12 -- instruction ) 0x38000000 rt-rn-im9-instruction ->post ;

( Address arithmetic )

: adr-x# ( rt relative ) 0x10000000 rt-im21-instruction ;


( Arithmetic )

: orr-xxx ( rt rn rm -- instruction ) 0xaa000000 rt-rn-rm-instruction ;
: orr-www ( rt rn rm -- instruction ) orr-xxx ->w ;

: add-xx# ( rt rn im12 -- instruction ) 0x91000000 rt-rn-im12-instruction ;
: add-xxx ( rt rm rn -- instruction )   0x8b000000 rt-rn-rm-instruction ;
: add-ww# ( rt rn im12 -- instruction ) add-xx# ->w ;
: add-www ( rt rm rn -- instruction )  add-xxx ->w ;

: sub-xx# ( rt rn im12 -- instruction ) 0xd1000000 rt-rn-im12-instruction ;
: sub-xxx ( rt rm rn -- instruction )   0xcb000000 rt-rn-rm-instruction ;
: sub-ww# ( rt rn im12 -- instruction ) sub-xx# ->w ;
: sub-www ( rt rm rn -- instruction )  sub-xxx ->w ;

: subs-xx# ( rt rn im12 -- instruction ) 0xf1000000 rt-rn-im12-instruction ;
: subs-ww# ( rt rn im12 -- instruction ) subs-xx# ->w ;

: cmp-x#  ( rn im12 -- instruction ) 0x1f  rot rot subs-xx# ;
: cmp-w#  ( rt im12 -- instruction )   cmp-x# ->w ;

: cmp-xx  \ rm rn -- instruction 
  1f rot rot
  eb000000 
;

: madd-xxxx ( rt rm rn ra -- instruction ) 0x9b000000 rt-rn-rm-ra-instruction ;
: mul-xxx ( rt rm rn -- instruction )   0x1f 0x9b000000 rt-rn-rm-ra-instruction ;
: mul-www ( rt rm rn -- instruction ) mul-xxx ->w ;


( Move )

: mov-xx ( rt rm -- instruction ) 0d31 swap orr-xxx ;
: mov-ww ( rt rm -- instruction ) 0d31 swap orr-www ;

: mov-x# ( rt im16 -- instruction) 0xd2800000 rt-im16-instruction ;
: mov-w# ( rt im16 -- instruction) 0xd2800000 rt-im16-instruction ->w ;


( Branches )

: cbz-x#  ( rt im19 -- instruction ) 0xb4000000 rt-im19-instruction ;
: cbnz-x# ( rt im19 -- instruction ) 0xb5000000 rt-im19-instruction ;
: svc-#   ( im16 -- instruction )    0xd4000001 im16-instruction ;
: hlt-# ( im16 -- instruction )      0xd4400000 im16-instruction ;

: ret-x ( rn -- instruction )  0xd65f0000 swap set-rn ;
: ret- ( -- instruction )      0d30 ret-x ;
: br-x ( rn -- instruction )   0xd61f0000 rn-instruction ;
: b-# ( im26 -- instruction )  0x14000000 swap set-im26 ;
: bl-# ( im26 -- instruction ) 0x94000000 swap set-im26 ;
: blr-x ( rn -- instruction )  0xd63f0000 rn-instruction ;


 ( Conditional branches. The fundimental instruction is b-cond + an
 instruction code. We predefine a few of the common cases. 
 Keep in mind that the jump is relative and multiplied by 4. )

: b-cond ( im19 cond -- instruction )
  0x54000000			( im19 cond instruction )
  swap ->cond			( im19 instruction )
  swap set-im19		
;

: beq-# ( im19 -- instruction ) cond-eq b-cond ;
: bne-# ( im19 -- instruction ) cond-ne b-cond ;
: blt-# ( im19 -- instruction ) cond-lt b-cond ;
: bgt-# ( im19 -- instruction ) cond-gt b-cond ;
: ble-# ( im19 -- instruction ) cond-le b-cond ;
: bge-# ( im19 -- instruction ) cond-ge b-cond ;

( System register instructions )

: sysreg 5 lshift constant ;

( See ARMARM Section D19 for system register encoding )
0b1101111100000000 sysreg CNTFRQ_EL0
0b1101111100010001 sysreg CNTP_CTL_EL0
0b1101111100011001 sysreg CNTV_CTL_EL0
0b1101111100010000 sysreg CNTP_TVAL_EL0
0b1101111100011000 sysreg CNTV_TVAL_EL0
0b1101111100000010 sysreg CNTVCT_EL0
0b1100011000000000 sysreg VBAR_EL1

: rt-sysreg-instruction swap set-rt or ;

: mrs-xr ( sysreg rt -- instruction ) 0xd5300000 rt-sysreg-instruction ;
: msr-rx ( rt sysreg -- instruction ) 0xd5100000 rt-sysreg-instruction ;

( Macros to push and pop a register from the data and returns stacks. )

0d28 constant psp
0d29 constant rsp

: pushrsp-x ( r -- instruction ) rsp -8 str-x[x#]! ;
: poprsp-x  ( r -- instruction ) rsp  8 ldr-x[x]# ;

: pushpsp-x ( r -- instruction ) psp -8 str-x[x#]! ;
: poppsp-x  ( r -- instruction ) psp  8 ldr-x[x]# ;

( Backward labels and address words )

variable loc-1b
variable loc-2b
variable loc-3b
variable loc-4b
variable loc-5b

: 1b: here @ loc-1b ! ;
: 2b: here @ loc-2b ! ;
: 3b: here @ loc-3b ! ;
: 4b: here @ loc-4b ! ;
: 5b: here @ loc-5b ! ;

: ->1b loc-1b @ here @ - 4 /  ;
: ->2b loc-3b @ here @ - 4 /  ;
: ->3b loc-3b @ here @ - 4 /  ;
: ->4b loc-4b @ here @ - 4 /  ;
: ->5b loc-5b @ here @ - 4 /  ;

 
( Forward labels and address words )

variable loc-1f
variable loc-2f
variable loc-3f
variable loc-4f
variable loc-5f

: ->1f here @ loc-1f !  0 ;
: ->2f here @ loc-2f !  0 ;
: ->3f here @ loc-3f !  0 ;
: ->4f here @ loc-4f !  0 ;
: ->5f here @ loc-5f !  0 ;

: word-offset ( addr1 addr2 -- word-offset )
  - 4 /
;

( Given a branch instruction and an offset, update
the instruction to jump to that offset. This word deals
with the two forms of relative jumps. )

: patch-jump-offset ( offset instruction -- instruction )
  dup 0xff000000 and
  0x14000000 = if
    swap set-im26
  else
    swap set-im19
  then
;

( Given the addr of a branch instruction to patch, patch the
  immediate offset with the difference between the instruction
  address and here. )
  
: patch-jump-forward  ( address of instruction to patch -- )
  dup not if          ( check for undefined jump )
    ." Forward jump not defined!"
    exit
  then
  here @ over         ( ins-addr here ins-addr  )
  word-offset         ( ins-addr offset )
  over                ( ins-addr offset ins-addr )
  w@                  ( ins-addr offset instruction-to-be-patched )
  patch-jump-offset   ( ins-addr patched-instruction )
  swap w!
;

: 1f: loc-1f @ patch-jump-forward loc-1f 0 ! ;
: 2f: loc-2f @ patch-jump-forward loc-2f 0 ! ;
: 3f: loc-3f @ patch-jump-forward loc-3f 0 ! ;
: 4f: loc-4f @ patch-jump-forward loc-4f 0 ! ;
: 5f: loc-5f @ patch-jump-forward loc-5f 0 ! ;

: clear-jump-addresses ( -- )
  0 loc-1b !
  0 loc-2b !
  0 loc-3b !
  0 loc-4b !
  0 loc-5b !
  0 loc-1f !
  0 loc-2f !
  0 loc-3f !
  0 loc-4f !
  0 loc-5f !
;

( Create a new primitive word and leave its definition
  open. You *must* complete the word with ;; or it will
  surly crash. )

: defprim
  create		( Create a new word )
  here @ dup 8- !       ( Put DFA into CFA )
;

( Close out an open primitive word. This is essentially
  the code for next in the assembly. )

: ;;
  0 0xa 8 ldr-x[x]#  w,
  1 0   ldr-x[x]   w,
  1     br-x       w,
  align			( Next word aligns )
  clear-jump-addresses  ( Prevent cross word jumps )
;


( Test out the assembler )

( Define a noop primitive. )

defprim do-nothing
;;


defprim -rot
  3 		poppsp-x w,
  2 		poppsp-x w,
  1 		poppsp-x w,
  3 		pushpsp-x w,
  1 		pushpsp-x w,
  2 		pushpsp-x w,
;;

defprim ?dup
  0 28 		ldr-x[x] w,
  0 0 		cmp-x# w,
  ->1f 		beq-f w,
  0 		pushpsp-x w,
  1f:
;;

defprim 1+
  0 		poppsp-x w,
  0 0 1 	add-xx# w,
  0 		pushpsp-x w,
;;

defprim 1-
  0 		poppsp-x w,
  0 0 1 	sub-xx# w,
  0 		pushpsp-x w,
;;

defprim 4+
  0 		poppsp-x w,
  0 0 4 	add-xx# w,
  0 		pushpsp-x w,
;;

defprim 4-
  0 		poppsp-x w,
  0 0 4 	sub-xx# w,
  0 		pushpsp-x w,
;;

defprim 8+
  0 		poppsp-x w,
  0 0 8 	add-xx# w,
  0 		pushpsp-x w,
;;

defprim 8-
  0 		poppsp-x w,
  0 0 8 	sub-xx# w,
  0 		pushpsp-x w,
;;

defprim lshift
  0 		poppsp-x w,
  1 		poppsp-x w,
  1 1 0 	lsl-xxx w,
  1 		pushpsp-x w,
;;

defprim rshift
  0 		poppsp-x w,
  1 		poppsp-x w,
  1 1 0 	lsr-xxx w,
  1 		pushpsp-x w,
;;

defprim <=
  1 		poppsp-x w,
  0 		poppsp-x w,
  0 1 		cmp-xx w,
  0 zr zr c-gt 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim >=
  1 		poppsp-x w,
  0 		poppsp-x w,
  0 1 		cmp-xx w,
  0 zr zr c-lt 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim 0=
  0 		poppsp-x w,
  0 zr 		cmp-xx w,
  0 zr zr c-ne 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim 0<>
  0 		poppsp-x w,
  0 zr 		cmp-xx w,
  0 zr zr c-eq 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim 0<
  0 		poppsp-x w,
  0 zr 		cmp-xx w,
  0 zr zr c-ge 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim 0>
  0 		poppsp-x w,
  0 zr 		cmp-xx w,
  0 zr zr c-le 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim 0<=
  0 		poppsp-x w,
  0 zr 		cmp-xx w,
  0 zr zr c-gt 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim 0>=
  0 		poppsp-x w,
  0 zr 		cmp-xx w,
  0 zr zr c-lt 	csinc-xxxc w,
  0 		pushpsp-x w,
;;

defprim xor
  1 		poppsp-x w,
  0 		poppsp-x w,
  0 1 0 	eor-xxx w,
  0 		pushpsp-x w,
;;

defprim +!
  0 		poppsp-x w,
  1 		poppsp-x w,
  2 0 		ldr-x[x] w,
  2 2 1 	add-xxx w,
  2 0 		str-x[x] w,
;;

defprim -!
  0 		poppsp-x w,
  1 		poppsp-x w,
  2 0 		ldr-x[x] w,
  2 2 1 	sub-xxx w,
  2 0 		str-x[x] w,
;;

defprim c!
  0 		poppsp-x w,
  1 		poppsp-x w,
  1 0 		strb-w[x] w,
;;

defprim c@
  0 		poppsp-x w,
  1 0 		ldrb-w[x] w,
  1 		pushpsp-x w,
;;

defprim c@c!
  0 28 8 	ldr-x[x#] w,
  1 28 		ldr-x[x] w,
  2 0 1 	ldrb-w[x]# w,
  2 1 1 	strb-w[x]# w,
  0 28 8 	str-x[x#] w,
  1 28 		str-x[x] w,
;;

defprim cmove
  0 		poppsp-x w,
  1 		poppsp-x w,
  2 		poppsp-x w,
  0 0 		cmp-x# w,
  ->2f 		b.eq-f w,
  1b:           ldrb w3, [x2], #1	
  3 2 1 	ldrb-w[x]# w,
  3 1 1 	strb-w[x]# w,
  0 0 1 	subs-xx# w,
  1b 		b.gt-b w,
  2f:
;;

defprim fence
  st 		dmb-st w,
;;

defprim dcc
  0 		poppsp-x w,
  cvac 0	dc-cvacx w,
;;

defprim dci
  0 		poppsp-x w,
  ivac 0 	dc-ivacx w,
;;

defprim dcci
  0 		poppsp-x w,
  civac 0 	dc-civacx w,
;;
