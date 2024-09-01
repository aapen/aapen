( Experiments in building a direct thread compiler )

( Test word that reads 3 words )

: echo-3-words ( -- )
  3
  begin dup 0>
  while
    word tell
    1-
  repeat
;

( Compile a word that simply calls out to some assembly code. )

: emit-call ( cfa -- )
	call-template 		( add the call instructions )
	call-template-len
	,*
	,			( and then the address we are calling )
;

( Compile a new word that simply calls out to some assembly code. )

: compile1 ( -- )
	create			( make a new word )
	here @ 8 + ,		( code address is the next word )
	call-template 		( call-t )
	call-template-len
	,*
	say-msg ,		( and then the f we are calling )
	ret-template 		( ret-t )
	ret-template-len
	,*
;

( Redefinable stubs )

: def
  create
  word find
  dup 0= if
	cr ." Not Found!" cr
	forget-latest
	drop
	exit
  then
  docol ,
  >cfa
  ,
  ' exit ,
;

: redef
  word find
  dup 0= if
	cr ." Not Found!" cr
	drop
	exit
  then
  >dfa
  word find
  dup 0= if
	cr ." Not Found!" cr
	2drop
	exit
  then
  >cfa
  swap !
;

( Create a rediect word)

compile1 word1

: normal-word-1 cr ." This is normal-word-1 " cr ;

: normal-word-2 cr ." This is normal-word-2 " cr ;

def redirect-word normal-word-1

redef redirect-word normal-word-2


