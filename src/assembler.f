noecho

( Save the current base and set it to hex )

variable assembler-save-base 

base @ assembler-save-base !
hex

( ARM assembler )

( Utility words that set fields on the instructions. )
: set-rt ( instruction rt - instruction )
  or
;

: set-ra ( instruction ra -- instruction )
  0b 11111 and
  0d 10 lshift
  or
;

: set-rn ( instruction rn -- instruction )
  0b 11111 and
  0d 5 lshift
  or
;

: set-rm ( instruction rm -- instruction )
  0b 11111 and
  0d 16 lshift
  or
;

: set-im21-hi ( instruction im21 -- instruction )
  0d 2 rshift 0d 5 lshift       ( instruction im21-hibits )
  or
;

: set-im21-low ( instruction im21 -- instruction )
  3 and 0d 29 lshift		( instruction im21-lowbits )
  or
;

: set-im26 ( instruction im26 -- instruction )
  3ffffff and			( instruction im26 )
  or
;

: set-im21 ( instruction im21 -- instruction )
  dup rot rot			( im21 instruction im21 )
  set-im21-hi			( im21 instruction )
  swap set-im21-low             ( instruction )
;

: set-im19 ( instruction im19 -- instruction )
  0b 1111111111111111111 and	( instruction im19 )
  0d 5 lshift                   ( instruction mask )
  or
;

: set-im16 ( instruction im16 -- instruction )
  0b 1111111111111111 and	( instruction im16 )
  0d 5 lshift                   ( instruction mask )
  or
;

: set-im12 ( instruction im12 -- instruction )
  0b 111111111111 and		( instruction im12 )
  0d 10 lshift                  ( instruction mask )
  or
;

: set-im9 ( instruction im9 -- instruction )
  0b 111111111 and		( instruction im9 )
  0d 12 lshift                  ( instruction mask )
  or
;

: set-im6 ( instruction im6 -- instruction )
  0b 111111 and			( instruction im6 )
  0d 10 lshift                  ( instruction mask )
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

: cond-eq 0b 0000 ;
: cond-ne 0b 0001 ;
: cond-cs 0b 0010 ;
: cond-cc 0b 0011 ;
: cond-mi 0b 0100 ;
: cond-pl 0b 0101 ;
: cond-vs 0b 0110 ;
: cond-vc 0b 0111 ;
: cond-hi 0b 1000 ;
: cond-ls 0b 1001 ;
: cond-ge 0b 1010 ;
: cond-lt 0b 1011 ;
: cond-gt 0b 1100 ;
: cond-le 0b 1101 ;
: cond-al 0b 1110 ;
: cond-nv 0b 1111 ;


( Instruction modifiers )

( Turn instruction into the 32 bit version of itself )

: ->w ( instruction -- instruction )
  7fffffff and		( clear bit 31 )
;

( Turn on the shift option )

: ->shift ( instruction -- instruction )
  1 0d 22 lshift
  or
;

( Set the condition code for a b-cond instruction )

: ->cond ( instruction cond -- instruction )
  0b 1111 and
  or
;

( Set the preindex option )

: ->pre ( instruction -- instruction )
  0b 11 0d 10 lshift
  or
;

( Set the postindex option )

: ->post ( instruction -- instruction )
  0b 01 0d 10 lshift
  or
;


( These are the actual assembler instructions. )

( Load and store )

( Note the immediate offsets are multiplied by 8 when executed )

: ldr-x[x]#  ( rt rn im12 -- instruction )  f8400000 rt-rn-im9-instruction ->post ;
: ldr-x[x]   ( rt rn      -- instruction )  0 f8400000 rt-rn-im9-instruction ;

: ldr-x[x#]! ( rt rn im12 -- instruction )  f8400000 rt-rn-im9-instruction ->pre ;
: ldr-x#     ( rt im19 -- instruction )     58000000 rt-im19-instruction ;

: ldrb-w[x]# ( rt rn im9 -- instruction ) 38400000 rt-rn-im9-instruction ->post ;
: ldrb-w[x]  ( rt rn     -- instruction ) 0 39400000 rt-rn-im12-instruction ;
: ldrb-w[x#] ( rt rn im12 -- instruction ) 39400000 rt-rn-im12-instruction ;

( TBD this has problems with neg imm values )

: ldr-x[x#]  ( rt rn im12 -- instruction )  f9400000 rt-rn-im12-instruction ;

: str-x[x#]! ( rt rn im12 -- instruction ) f8000000 rt-rn-im9-instruction ->pre ;
: str-x[x#]  ( rt rn im12 -- instruction ) f8000000 rt-rn-im9-instruction ;
: str-x[x]#  ( rt rn im12 -- instruction ) f8000000 rt-rn-im9-instruction ->post ;

: strb-w[x#]  ( rt rn im12 -- instruction ) 39000000 rt-rn-im12-instruction ;
: strb-w[x]   ( rt rn im12 -- instruction ) 0 strb-w[x#] ;
: strb-w[x]#  ( rt rn im12 -- instruction ) 38000000 rt-rn-im9-instruction ->post ;

( Address arithmetic )

: adr-x# ( rt relative ) 10000000 rt-im21-instruction ;


( Arithmetic )

: orr-xxx ( rt rn rm -- instruction ) aa000000 rt-rn-rm-instruction ;
: orr-www ( rt rn rm -- instruction ) orr-xxx ->w ;

: add-xx# ( rt rn im12 -- instruction ) 91000000 rt-rn-im12-instruction ;
: add-xxx ( rt rm rn -- instruction )   8b000000 rt-rn-rm-instruction ;
: add-ww# ( rt rn im12 -- instruction ) add-xx# ->w ;
: add-www ( rt rm rn -- instruction )  add-xxx ->w ;

: sub-xx# ( rt rn im12 -- instruction ) d1000000 rt-rn-im12-instruction ;
: sub-xxx ( rt rm rn -- instruction )   cb000000 rt-rn-rm-instruction ;
: sub-ww# ( rt rn im12 -- instruction ) sub-xx# ->w ;
: sub-www ( rt rm rn -- instruction )  sub-xxx ->w ;

: subs-xx# ( rt rn im12 -- instruction ) f1000000 rt-rn-im12-instruction ;
: subs-ww# ( rt rn im12 -- instruction ) subs-xx# ->w ;

: cmp-x#  ( rn im12 -- instruction ) 1f  rot rot subs-xx# ;
: cmp-w#  ( rt im12 -- instruction )   cmp-x# ->w ;

: madd-xxxx ( rt rm rn ra -- instruction ) 9b000000 rt-rn-rm-ra-instruction ;
: mul-xxx ( rt rm rn -- instruction )   1f 9b000000 rt-rn-rm-ra-instruction ;
: mul-www ( rt rm rn -- instruction ) mul-xxx ->w ;


( Move )

: mov-xx ( rt rm -- instruction ) 0d 31 swap orr-xxx ;
: mov-ww ( rt rm -- instruction ) 0d 31 swap orr-www ;

: mov-x# ( rt im16 -- instruction) d2800000 rt-im16-instruction ;
: mov-w# ( rt im16 -- instruction) d2800000 rt-im16-instruction ->w ;


( Branches )

: cbz-x#  ( rt im19 -- instruction ) b4000000 rt-im19-instruction ;
: cbnz-x# ( rt im19 -- instruction ) b5000000 rt-im19-instruction ;
: svc-#   ( im16 -- instruction )    d4000001 im16-instruction ;
: hlt-# ( im16 -- instruction ) 0x d4400000 im16-instruction ;

: ret-x ( rn -- instruction )  d65f0000 swap set-rn ;
: ret- ( -- instruction ) 0d 30 ret-x ;
: br-x ( rn -- instruction )   d61f0000 rn-instruction ;
: b-# ( im26 -- instruction )  14000000 swap set-im26 ;
: bl-# ( im26 -- instruction ) 94000000 swap set-im26 ;
: blr-x ( rn -- instruction )  d63f0000 rn-instruction ;


 ( Conditional branches. The fundimental instruction is b-cond + an
 instruction code. We predefine a few of the common cases. 
 Keep in mind that the jump is relative and multiplied by 4. )

: b-cond ( im19 cond -- instruction )
  0x 54000000			( im19 cond instruction )
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
0b 1101111100000000 sysreg CNTFRQ_EL0
0b 1101111100010001 sysreg CNTP_CTL_EL0
0b 1101111100011001 sysreg CNTV_CTL_EL0
0b 1101111100010000 sysreg CNTP_TVAL_EL0
0b 1101111100011000 sysreg CNTV_TVAL_EL0
0b 1101111100000010 sysreg CNTVCT_EL0
0b 1100011000000000 sysreg VBAR_EL1

: rt-sysreg-instruction swap set-rt or ;

: mrs-xr ( sysreg rt -- instruction ) d5300000 rt-sysreg-instruction ;
: msr-rx ( rt sysreg -- instruction ) d5100000 rt-sysreg-instruction ;

( Macros to push and pop a register from the data and returns stacks. )

0d 28 constant psp
0d 29 constant rsp

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
  dup ff000000 and
  14000000 = if
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
  here @ 8 + ,		( Code word is the next address )
;

( Close out an open primitive word. This is essentially
  the code for next in the assembly. )

: ;;
  0 a 8 ldr-x[x]#  w,
  1 0   ldr-x[x]   w,
  1     br-x       w,
  align			( Next word aligns )
  clear-jump-addresses  ( Prevent cross word jumps )
;


( Test out the assembler )

decimal

( Define a noop primitive. )

defprim do-nothing
;;


( Push 44 onto the data stack )

defprim x-push-44
  0  44     mov-x#     w,
  0         pushpsp-x  w,
;;

( branch link to the 64b address on the TOS. )

defprim call ( addr -- ?? )
  0        poppsp-x    w,
  0        blr-x       w,
;;

( compile a call to the addr on the TOS )

: compile-call ( addr -- )
  30 24 adr-x#   w,
  17 12 adr-x#   w,
  17 17 ldr-x[x] w,
  17    br-x     w,
  ,
;

( Call the assembly lang f say-msg twice )

defprim x-say-msg
  say-msg compile-call
  say-msg compile-call
;;

( Copy of the dup word )

defprim x-dup
  0  psp    ldr-x[x]   w,
  0         pushpsp-x  w,
;;

( Copy of the drop word )

defprim x-drop
  psp psp 8 add-xx#    w,
;;

( Copy of the rot word )

defprim x-rot
  3         poppsp-x   w,
  2         poppsp-x   w,
  1         poppsp-x   w,
  2         pushpsp-x  w,
  3         pushpsp-x  w,
  1         pushpsp-x  w,
;;

( This is a copy of the cmove word, testing out labels and jumps )

defprim x-cmove ( src-addr dst-addr len -- )
  0         poppsp-x   w,
  1         poppsp-x   w,
  2         poppsp-x   w,
  0 0       cmp-x#     w,
  ->2f      beq-#      w,
  1b:
  3 2 1     ldrb-w[x]# w,
  3 1 1     strb-w[x]# w,
  0 0 1     subs-xx#   w,
  ->1b      bgt-#      w,
  2f:
;;

assembler-save-base @ base !
echo

