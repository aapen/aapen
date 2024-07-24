noecho

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

( Compile a new word that simply calls out to some assembly code. )

: compile1 ( -- )
	word create		( make a new word )
	here @ 8 + ,		( code address is the next word )
	call-template 		( call-t )
	call-template-len
	,*
	say-msg ,		( and then the f we are calling )
	ret-template 		( ret-t )
	ret-template-len
	,*
;

( Create a new word )

compile1 word1

echo

