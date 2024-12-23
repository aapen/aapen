\ test cases drawn from https://forth-standard.org
\
\ exercise these with `testsuite evaluate`
\
\ A general note on test structure: these test stanzas do not stand
\ alone and independent. They often define words that are used later
\ by other tests. This makes them stateful, coupled, and all that. Be
\ cautious when reordering the blocks in this file.
\
\ A note on input and output: There is no mechanism in the Forth
\ standard for capturing output -- though of course some systems have
\ their own non-standard mechanism. We just don't have one in
\ Aapen. That means the output tests can only be verified by visual
\ inspection.
\
\ I have also omitted tests for double-cell math and logic. With a
\ 64-bit cell size, the double words are an unnecessary complication.

hex

.\ F.3		Basic Assumptions
t{ -> }t \ test the test harness
t{ : bitsset? if 0 0 else 0 then ; -> }t \ test if any bits are set, answer in base 1
t{ 0 bitsset? -> 0 }t                    \ zero is all bits clear
t{ 1 bitsset? -> 0 0 }t                  \ other numbers have at least one bit
t{ -1 bitsset? -> 0 0 }t

.\ F.3.2		Booleans
t{ 0 0 and -> 0 }t
t{ 0 1 and -> 0 }t
t{ 1 0 and -> 0 }t
t{ 1 1 and -> 1 }t

t{ 0 invert 1 and -> 1 }t
t{ 1 invert 1 and -> 0 }t

0        constant 0s
0 invert constant 1s

t{ 0s invert -> 1s }t
t{ 1s invert -> 0s }t

t{ 0s 0s and -> 0s }t
t{ 0s 1s and -> 0s }t
t{ 1s 0s and -> 0s }t
t{ 1s 1s and -> 1s }t

t{ 0s 0s or -> 0s }t
t{ 0s 1s or -> 1s }t
t{ 1s 0s or -> 1s }t
t{ 1s 1s or -> 1s }t

t{ 0s 0s xor -> 0s }t
t{ 0s 1s xor -> 1s }t
t{ 1s 0s xor -> 1s }t
t{ 1s 1s xor -> 0s }t

.\ F.3.3		Shifts
1s 1 rshift invert constant msb
t{ msb bitsset? -> 0 0 }t

.\ F.6.1.0320	2*
t{   0s 2*       ->   0s }t
t{    1 2*       ->    2 }t
t{ 4000 2*       -> 8000 }t
t{   1s 2* 1 xor ->   1s }t
t{  msb 2*       ->   0s }t

.\ F.6.1.0330	2/
t{          0s 2/ ->   0s }t
t{           1 2/ ->    0 }t
t{        4000 2/ -> 2000 }t
\ t{          1s 2/ ->   1s }t
t{    1s 1 xor 2/ ->   1s }t
t{ msb 2/ msb and ->  msb }t

.\ F.6.1.1805	lshift
t{   1 0 lshift       ->    1 }t
t{   1 1 lshift       ->    2 }t
t{   1 2 lshift       ->    4 }t
t{   1 f lshift       -> 8000 }t
t{  1s 1 lshift 1 xor ->   1s }t
t{ msb 1 lshift       ->    0 }t

.\ F.6.1.2162	rshift
t{ 1 0    rshift         -> 1 }t
t{ 1 1    rshift         -> 0 }t
t{ 2 1    rshift         -> 1 }t
t{ 4 2    rshift         -> 1 }t
t{ 8000 f rshift         -> 1 }t
t{ msb 1  rshift msb and -> 0 }t      \ rshift zero fills msbs
t{ msb 1  rshift 2*      -> msb }t

.\ F.3.5		Comparisons
0 invert constant max-uint
0 invert 1 rshift constant max-int
0 invert 1 rshift invert constant min-int
0 invert 1 rshift constant mid-uint
0 invert 1 rshift invert constant mid-uint+1

0s constant <false>
1s constant <true>

.\ F.6.1.0250	0<
t{       0 0< -> <false> }t
t{      -1 0< -> <true>  }t
t{ min-int 0< -> <true>  }t
t{       1 0< -> <false> }t
t{ max-int 0< -> <false> }t

.\ F.6.1.0270	0=
t{        0 0= -> <true>  }t
t{        1 0= -> <false> }t
t{        2 0= -> <false> }t
t{       -1 0= -> <false> }t
t{ max-uint 0= -> <false> }t
t{  min-int 0= -> <false> }t
t{  max-int 0= -> <false> }t

.\ F.6.1.0290	1+
t{        0 1+ -> 1          }t
t{       -1 1+ -> 0          }t
t{        1 1+ -> 2          }t
t{ mid-uint 1+ -> mid-uint+1 }t

.\ F.6.1.0300	1-
t{          2 1- -> 1        }t
t{          1 1- -> 0        }t
t{          0 1- -> -1       }t
t{ mid-uint+1 1- -> mid-uint }t

.\ F.6.1.0480	<
t{ 0 1             < -> <true>  }t
t{ 1 2             < -> <true>  }t
t{ -1 0            < -> <true>  }t
t{ -1 1            < -> <true>  }t
t{ min-int 0       < -> <true>  }t
t{ min-int max-int < -> <true>  }t
t{ 0 max-int       < -> <true>  }t
t{ 0 0             < -> <false> }t
t{ 1 1             < -> <false> }t
t{ 1 0             < -> <false> }t
t{ 2 1             < -> <false> }t
t{ 0 -1            < -> <false> }t
t{ 1 -1            < -> <false> }t
t{ 0 min-int       < -> <false> }t
t{ max-int min-int < -> <false> }t
t{ max-int 0       < -> <false> }t

.\ F.6.1.0530	=
t{  0  0 = -> <true>  }t
t{  1  1 = -> <true>  }t
t{ -1 -1 = -> <true>  }t
t{  1  0 = -> <false> }t
t{ -1  0 = -> <false> }t
t{  0  1 = -> <false> }t
t{  0 -1 = -> <false> }t

.\ F.6.1.0540	>
t{ 0 1             > -> <false> }t
t{ 1 2             > -> <false> }t
t{ -1 0            > -> <false> }t
t{ -1 1            > -> <false> }t
t{ min-int 0       > -> <false> }t
t{ min-int max-int > -> <false> }t
t{ 0 max-int       > -> <false> }t
t{ 0 0             > -> <false> }t
t{ 1 1             > -> <false> }t
t{ 1 0             > -> <true>  }t
t{ 2 1             > -> <true>  }t
t{ 0 -1            > -> <true>  }t
t{ 1 -1            > -> <true>  }t
t{ 0 min-int       > -> <true>  }t
t{ max-int min-int > -> <true>  }t
t{ max-int 0       > -> <true>  }t

.\ F.6.1.2340	u<
t{        0        1 u< -> <true>  }t
t{        1        2 u< -> <true>  }t
t{        0 mid-uint u< -> <true>  }t
t{        0 max-uint u< -> <true>  }t
t{ mid-uint max-uint u< -> <true>  }t
t{        0        0 u< -> <false> }t
t{        1        1 u< -> <false> }t
t{        1        0 u< -> <false> }t
t{        2        1 u< -> <false> }t
t{ mid-uint        0 u< -> <false> }t
t{ max-uint        0 u< -> <false> }t
t{ max-uint mid-uint u< -> <false> }t

.\ F.6.1.1870	max
t{ 0 1             max -> 1       }t
t{ 1 2             max -> 2       }t
t{ -1 0            max -> 0       }t
t{ -1 1            max -> 1       }t
t{ min-int 0       max -> 0       }t
t{ min-int max-int max -> max-int }t
t{ 0 max-int       max -> max-int }t
t{ 0 0             max -> 0       }t
t{ 1 1             max -> 1       }t
t{ 1 0             max -> 1       }t
t{ 2 1             max -> 2       }t
t{ 0 -1            max -> 0       }t
t{ 1 -1            max -> 1       }t
t{ 0 min-int       max -> 0       }t
t{ max-int min-int max -> max-int }t
t{ max-int 0       max -> max-int }t

.\ F.6.1.1880	min
t{ 0 1             min -> 0       }t
t{ 1 2             min -> 1       }t
t{ -1 0            min -> -1      }t
t{ -1 1            min -> -1      }t
t{ min-int 0       min -> min-int }t
t{ min-int max-int min -> min-int }t
t{ 0 max-int       min -> 0       }t
t{ 0 0             min -> 0       }t
t{ 1 1             min -> 1       }t
t{ 1 0             min -> 0       }t
t{ 2 1             min -> 1       }t
t{ 0 -1            min -> -1      }t
t{ 1 -1            min -> -1      }t
t{ 0 min-int       min -> min-int }t
t{ max-int min-int min -> min-int }t
t{ max-int 0       min -> 0       }t

.\ F.3.6		Stack Operators
.\ F.6.1.1260	drop
t{ 1 2 drop -> 1 }t
t{ 0 drop -> }t

.\ F.6.1.1290	dup
t{ 1 dup -> 1 1 }t

.\ F.6.1.1990	over
t{ 1 2 over -> 1 2 1 }t

.\ F.6.1.2160	rot
t{ 1 2 3 rot -> 2 3 1 }t

.\ F.6.1.2260	swap
t{ 1 2 swap -> 2 1 }t

.\ F.6.1.0370	2drop
t{ 1 2 2drop -> }t

.\ F.6.1.0380	2dup
t{ 1 2 2dup -> 1 2 1 2 }t

.\ F.6.1.0400	2over
t{ 1 2 3 4 2over -> 1 2 3 4 1 2 }t

.\ F.6.1.0430	2swap
t{ 1 2 3 4 2swap -> 3 4 1 2 }t

.\ F.6.1.0630	?dup
t{ -1 ?dup -> -1 -1 }t
t{  0 ?dup ->  0    }t
t{  1 ?dup ->  1  1 }t

.\ F.6.1.1200	depth
\ these don't work right now because 'evaluate' puts 6 things on the stack before we start the tests.
\ t{ 0 1 depth -> 0 1 2 }t
\ t{   0 depth -> 0 1   }t
\ t{     depth -> 0     }t

.\ F.3.7		Return Stack Operators
.\ F.6.1.0850	>r r> r@
t{ : gr1 >r r> ; -> }t
t{ : gr2 >r r@ r> drop ; -> }t
t{ 123 gr1 -> 123 }t
t{ 123 gr2 -> 123 }t
t{  1s gr1 -> 1s }t

.\ F.3.8		Addition and Subtraction
.\ F.6.1.0120	+
t{        0  5 + ->          5 }t
t{        5  0 + ->          5 }t
t{        0 -5 + ->         -5 }t
t{       -5  0 + ->         -5 }t
t{        1  2 + ->          3 }t
t{        1 -2 + ->         -1 }t
t{       -1  2 + ->          1 }t
t{       -1 -2 + ->         -3 }t
t{       -1  1 + ->          0 }t
t{ mid-uint  1 + -> mid-uint+1 }t

.\ F.6.1.0160	-
t{          0  5 - ->       -5 }t
t{          5  0 - ->        5 }t
t{          0 -5 - ->        5 }t
t{         -5  0 - ->       -5 }t
t{          1  2 - ->       -1 }t
t{          1 -2 - ->        3 }t
t{         -1  2 - ->       -3 }t
t{         -1 -2 - ->        1 }t
t{          0  1 - ->       -1 }t
t{ mid-uint+1  1 - -> mid-uint }t

.\ F.6.1.0290	1+
t{        0 1+ ->          1 }t
t{       -1 1+ ->          0 }t
t{        1 1+ ->          2 }t
t{ mid-uint 1+ -> mid-uint+1 }t

.\ F.6.1.0300	1-
t{          2 1- ->        1 }t
t{          1 1- ->        0 }t
t{          0 1- ->       -1 }t
t{ mid-uint+1 1- -> mid-uint }t

.\ F.6.1.0690	abs
t{        0 1+ ->          1 }t
t{       -1 1+ ->          0 }t
t{        1 1+ ->          2 }t
t{ mid-uint 1+ -> mid-uint+1 }t

.\ F.6.1.1910	negate
t{  0 negate ->  0 }t
t{  1 negate -> -1 }t
t{ -1 negate ->  1 }t
t{  2 negate -> -2 }t
t{ -2 negate ->  2 }t

.\ F.3.9		Multiplication
.\ F.6.1.2170	s>d (not implemented)
.\ F.6.1.0090	*
t{  0  0 * ->  0 }t          \ test identities
t{  0  1 * ->  0 }t
t{  1  0 * ->  0 }t
t{  1  2 * ->  2 }t
t{  2  1 * ->  2 }t
t{  3  3 * ->  9 }t
t{ -3  3 * -> -9 }t
t{  3 -3 * -> -9 }t
t{ -3 -3 * ->  9 }t
t{ mid-uint+1 1 rshift 2 *               -> mid-uint+1 }t
t{ mid-uint+1 2 rshift 4 *               -> mid-uint+1 }t
t{ mid-uint+1 1 rshift mid-uint+1 or 2 * -> mid-uint+1 }t

.\ F.6.1.1810	m*		(not implemented)
.\ F.6.1.2360	um*		(not implemented)

.\ F.3.10		Division
\ these differ from the test cases at
\ https://forth-standard.org/standard/testsuite#test:core:/MOD
\ because /mod is primitive for us and we do not need sm/rem or fm/mod

.\ F.6.1.1561	fm/mod		(not implemented)
.\ F.6.1.2214	sm/rem		(not implemented)
.\ F.6.1.2370	um/mod		(not implemented)
.\ F.6.1.0240	/mod
t{       0       1 /mod ->       0       0 }t
t{       1       1 /mod ->       0       1 }t
t{       2       1 /mod ->       0       2 }t
t{      -1       1 /mod ->       0      -1 }t
t{      -2       1 /mod ->       0      -2 }t
t{       0      -1 /mod ->       0       0 }t
t{       1      -1 /mod ->       0      -1 }t
t{       2      -1 /mod ->       0      -2 }t
t{      -1      -1 /mod ->       0       1 }t
t{      -2      -1 /mod ->       0       2 }t
t{       2       2 /mod ->       0       1 }t
t{      -1      -1 /mod ->       0       1 }t
t{      -2      -2 /mod ->       0       1 }t
t{       7       3 /mod ->       1       2 }t
t{       7      -3 /mod ->       1      -2 }t
t{      -7       3 /mod ->      -1      -2 }t
t{      -7      -3 /mod ->      -1       2 }t
t{ max-int       1 /mod ->       0 max-int }t
t{ min-int       1 /mod ->       0 min-int }t
t{ max-int max-int /mod ->       0       1 }t
t{ min-int min-int /mod ->       0       1 }t

.\ F.6.1.0230	/
t{       0       1 /    ->       0         }t
t{       1       1 /    ->       1         }t
t{       2       1 /    ->       2         }t
t{      -1       1 /    ->      -1         }t
t{      -2       1 /    ->      -2         }t
t{       0      -1 /    ->       0         }t
t{       1      -1 /    ->      -1         }t
t{       2      -1 /    ->      -2         }t
t{      -1      -1 /    ->       1         }t
t{      -2      -1 /    ->       2         }t
t{       2       2 /    ->       1         }t
t{      -1      -1 /    ->       1         }t
t{      -2      -2 /    ->       1         }t
t{       7       3 /    ->       2         }t
t{       7      -3 /    ->      -2         }t
t{      -7       3 /    ->      -2         }t
t{      -7      -3 /    ->       2         }t
t{ max-int       1 /    -> max-int         }t
t{ min-int       1 /    -> min-int         }t
t{ max-int max-int /    ->       1         }t
t{ min-int min-int /    ->       1         }t

.\ F.6.1.1890	mod
t{       0       1 mod  -> 0               }t
t{       1       1 mod  -> 0               }t
t{       2       1 mod  -> 0               }t
t{      -1       1 mod  -> 0               }t
t{      -2       1 mod  -> 0               }t
t{       0      -1 mod  -> 0               }t
t{       1      -1 mod  -> 0               }t
t{       2      -1 mod  -> 0               }t
t{      -1      -1 mod  -> 0               }t
t{      -2      -1 mod  -> 0               }t
t{       2       2 mod  -> 0               }t
t{      -1      -1 mod  -> 0               }t
t{      -2      -2 mod  -> 0               }t
t{       7       3 mod  -> 1               }t
t{       7      -3 mod  -> 1               }t
t{      -7       3 mod  -> -1              }t
t{      -7      -3 mod  -> -1              }t
t{ max-int       1 mod  -> 0               }t
t{ min-int       1 mod  -> 0               }t
t{ max-int max-int mod  -> 0               }t
t{ min-int min-int mod  -> 0               }t

.\ F.6.1.0100	*/
t{       0 2       1 */ ->       0  }t
t{       1 2       1 */ ->       2  }t
t{       2 2       1 */ ->       4  }t
t{      -1 2       1 */ ->      -2  }t
t{      -2 2       1 */ ->      -4  }t
t{       0 2      -1 */ ->       0  }t
t{       1 2      -1 */ ->      -2  }t
t{       2 2      -1 */ ->      -4  }t
t{      -1 2      -1 */ ->       2  }t
t{      -2 2      -1 */ ->       4  }t
t{       2 2       2 */ ->       2  }t
t{      -1 2      -1 */ ->       2  }t
t{      -2 2      -2 */ ->       2  }t
t{       7 2       3 */ ->       4  }t
t{       7 2      -3 */ ->      -4  }t
t{      -7 2       3 */ ->      -4  }t
t{      -7 2      -3 */ ->       4  }t
t{ max-int 2 max-int */ ->       0  }t
t{ min-int 2 min-int */ ->       0  }t

.\ F.6.1.0110	*/mod
t{       0 2       1 */mod ->  0  0   }t
t{       1 2       1 */mod ->  0  2   }t
t{       2 2       1 */mod ->  0  4   }t
t{      -1 2       1 */mod ->  0 -2   }t
t{      -2 2       1 */mod ->  0 -4   }t
t{       0 2      -1 */mod ->  0  0   }t
t{       1 2      -1 */mod ->  0 -2   }t
t{       2 2      -1 */mod ->  0 -4   }t
t{      -1 2      -1 */mod ->  0  2   }t
t{      -2 2      -1 */mod ->  0  4   }t
t{       2 2       2 */mod ->  0  2   }t
t{      -1 2      -1 */mod ->  0  2   }t
t{      -2 2      -2 */mod ->  0  2   }t
t{       7 2       3 */mod ->  2  4   }t
t{       7 2      -3 */mod ->  2 -4   }t
t{      -7 2       3 */mod -> -2 -4   }t
t{      -7 2      -3 */mod -> -2  4   }t
t{ max-int 2 max-int */mod -> -2  0   }t \ overflow case
t{ min-int 2 min-int */mod ->  0  0   }t \ overflow case

.\ F.3.11		Memory
.\ F.6.1.0150	,
here 1 ,
here 2 ,
constant 2nd
constant 1st
t{ 1st 2nd u<     -> <true> }t
t{ 1st cell+      -> 2nd    }t
t{ 1st 1 cells +  -> 2nd    }t
t{ 1st @ 2nd @    -> 1 2    }t
t{ 5 1st !        ->        }t
t{ 1st @ 2nd @    -> 5 2    }t
t{ 6 2nd !        ->        }t
t{ 1st @ 2nd @    -> 5 6    }t
t{ 1st 2@         -> 6 5    }t
t{ 2 1 1st 2!     ->        }t
t{ 1st 2@         -> 2 1    }t
t{ 1s 1st ! 1st @ -> 1s     }t

.\ F.6.1.0130	+!
t{         0 1st ! ->   }t
t{        1 1st +! ->   }t
t{           1st @ -> 1 }t
t{ -1 1st +! 1st @ -> 0 }t

.\ F.6.1.0890	cells
: bits ( x -- u )
  0 swap begin
    dup
  while
    dup msb and if >r 1+ r> then 2*
  repeat drop ;
t{         1 cells 1 < -> <false> }t
t{ 1 cells 1 chars mod -> 0       }t
t{        1s bits 10 < -> <false> }t

.\ F.6.1.0860	c,
here 1 c,
here 2 c,
constant 2ndc
constant 1stc
t{    1stc 2ndc u< -> <true> }t
t{      1stc char+ -> 2ndc   }t
t{  1stc 1 chars + -> 2ndc   }t
t{ 1stc c@ 2ndc c@ -> 1 2    }t
t{       3 1stc c! ->        }t
t{ 1stc c@ 2ndc c@ -> 3 2    }t
t{       4 2ndc c! ->        }t
t{ 1stc c@ 2ndc c@ -> 3 4    }t


.\ F.6.1.0898	chars
t{       1 chars 1 < -> <false> }t \ chars is at least 1 byte
t{ 1 chars 1 cells > -> <false> }t \ chars is smaller than a cell

.\ F.6.1.0705	align
align 1 allot here align here 3 cells allot
constant a-addr constant ua-addr
t{ ua-addr aligned -> a-addr                          }t \ check alignment works
t{       1 a-addr c!       a-addr       c@ -> 1       }t \ aligned access is ok for chars
t{    1234 a-addr !        a-addr       @  -> 1234    }t
t{ 123 456 a-addr 2!       a-addr       2@ -> 123 456 }t
t{       2 a-addr char+ c! a-addr char+ c@ -> 2       }t \ unaligned access is ok for chars
t{       3 a-addr cell+ c! a-addr cell+ c@ -> 3       }t
t{    1234 a-addr cell+ !  a-addr cell+ @  -> 1234    }t
t{ 123 456 a-addr cell+ 2! a-addr cell+ 2@ -> 123 456 }t

.\ F.6.1.0710	allot
here 1 allot
here
constant 2nda
constant 1sta
t{ 1sta 2nda u< -> <true> }t \ here must grow with allot
t{      1sta 1+ -> 2nda   }t \ by one address unit

.\ F.3.12		Characters
.\ F.6.1.0770	bl
t{ bl -> 20 }t

.\ F.6.1.0895	char
t{     char x -> 0x78 }t
t{ char hello -> 0x68 }t

.\ F.6.1.2520	[char]
t{ : gc1 [char] X ; -> }t
t{ : gc2 [char] HELLO ; -> }t
t{ gc1 -> 0x58 }t
t{ gc2 -> 0x48 }t

.\ F.6.1.2500	[ and ]
t{ : gc3 [ gc1 ] literal ; -> }t
t{ gc3 -> 0x58 }t

.\ F.6.1.2165	s"
t{ : gc4 s" XY" ; -> }t
t{ gc4 swap drop -> 2 }t
t{ gc4 drop dup c@ swap char+ c@ -> 0x58 0x59 }t
: gc5 s" A String"2drop ; \ there is no space between the " and 2drop
t{ gc5 -> }t

.\ F.3.13		Dictionary
.\ F.6.1.0070	'
t{ : gt1 123 ;   ->     }t
t{ ' gt1 execute -> 123 }t

.\ F.6.1.2510	[']
t{ : gt2 ['] gt1 ; immediate -> }t
t{ gt2 execute -> 123 }t

.\ F.6.1.1550	find

\ TODO: [wordfind] MTN - These fail because our `find` expects ( caddr u ) but the standard expects
\ a counted string

\ leave these uncommented because they are used later
here 3 c, char g c, char t c, char 1 c, constant gt1string
here 3 c, char g c, char t c, char 2 c, constant gt2string
\ t{ gt1string find -> ' gt1 -1 }t
\ t{ gt2string find -> ' gt2  1 }t

.\ F.6.1.1780	literal
t{ : gt3 gt2 literal ; -> }t
t{ gt3 -> ' gt1 }t

.\ F.6.1.0980	count
t{ gt1string count -> gt1string char+ 3 }t

.\ F.6.1.2033	postpone
t{ : gt4 postpone gt1 ; immediate -> }t
t{ : gt5 gt4 ; -> }t
t{ gt5 -> 123 }t
t{ : gt6 345 ; immediate -> }t

\ TODO: MTN - this is failing I know not why

\ t{ : gt7 postpone gt6 ; ->     }t
\ t{ gt7                  -> 345 }t

.\ F.6.1.2250	state
t{ : gt8 state @ ; immediate -> }t
t{ gt8 -> 0 }t
t{ : gt9 gt8 literal ; -> }t
t{ gt9 0= -> <false> }t

.\ F.3.14		Flow Control
.\ F.6.1.1700	if else then
t{ : gi1 if 123 then ; -> }t
t{ : gi2 if 123 else 234 then ; -> }t
t{   0 gi1 ->     }t
t{   1 gi1 -> 123 }t
t{  -1 gi1 -> 123 }t
t{   0 gi2 -> 234 }t
t{   1 gi2 -> 123 }t
t{  -1 gi2 -> 123 }t

\ multiple elses in an if statement (?!)
: melse if 1 else 2 else 3 else 4 else 5 then ;
t{ <false> melse -> 2 4 }t
t{ <true>  melse -> 1 3 5 }t

.\ F.6.1.2430	begin while repeat
t{ : gi3 begin dup 5 < while dup 1+ repeat ; -> }t
t{ 0 gi3 -> 0 1 2 3 4 5 }t
t{ 4 gi3 -> 4 5 }t
t{ 5 gi3 -> 5 }t
t{ 6 gi3 -> 6 }t

\ TODO: [while] MTN - I don't understand gi5 at all. The double `while` with only one `begin` and
\ `repeat` throws me. It also causes a core abort

\ t{ : gi5 begin dup 2 > while dup 5 < while dup 1+ repeat 123 else 345 then ; -> }t
\ t{ 1 gi5 -> 1 345 }t
\ t{ 2 gi5 -> 2 345 }t
\ t{ 3 gi5 -> 3 4 5 123 }t
\ t{ 4 gi5 -> 4 5 123 }t
\ t{ 5 gi5 -> 5 123 }t

.\ F.6.1.2390	begin until
t{ : gi4 begin dup 1+ dup 5 > until ; -> }t
t{ 3 gi4 -> 3 4 5 6 }t
t{ 5 gi4 -> 5 6 }t
t{ 6 gi4 -> 6 7 }t

.\ F.6.1.2120	recurse
t{ : gi6 dup if dup >r 1- recurse r> then ; -> }t
t{ 0 gi6 -> 0 }t
t{ 1 gi6 -> 0 1 }t
t{ 2 gi6 -> 0 1 2 }t
t{ 3 gi6 -> 0 1 2 3 }t
t{ 4 gi6 -> 0 1 2 3 4 }t
t{ :noname dup if dup >r 1- recurse r> then ; constant rn1 -> }t
t{ 0 rn1 execute -> 0 }t
t{ 4 rn1 execute -> 0 1 2 3 4 }t
decimal
:noname 1- dup case
          0 of exit endof
          1 of 11 swap recurse endof
          2 of 22 swap recurse endof
          3 of 33 swap recurse endof
          drop abs recurse exit
        endcase
; constant rn2
t{  1 rn2 execute -> 0 }t
t{  2 rn2 execute -> 11 0 }t
t{  4 rn2 execute -> 33 22 11 0 }t
t{ 25 rn2 execute -> 33 22 11 0 }t
hex

.\ F.3.15		Counted Loops
.\ F.6.1.1800	loop
t{ : gd1 do i loop ; -> }t
t{ 4 1 gd1 -> 1 2 3 }t
t{ 2 -1 gd1 -> -1 0 1 }t
t{ mid-uint+1 mid-uint gd1 -> mid-uint }t

.\ F.6.1.0140	+loop
\ TODO: [loop] MTN - These fail because my current implementation of +loop doesn't work with
\ negative increments

\ t{ : gd2 do i -1 +loop ; -> }t
\ t{ 1 4 gd2 -> 4 3 2 1 }t
\ t{ -1 2 gd2 -> 2 1 0 -1 }t
\ t{ mid-uint mid-uint+1 gd2 -> mid-uint+1 mid-uint }t
\ variable gditerations
\ variable gdincrement
\ : gd7
\   gdincrement !
\   0 gditerations !
\   do
\     1 gditerations +!
\     i
\     gditerations @ 6 = if leave then
\     gdincrement @
\   +loop
\   gditerations @
\ ;
\ t{    4  4  -1 gd7 ->  4                  1  }t
\ t{    1  4  -1 gd7 ->  4  3  2  1         4  }t
\ t{    4  1  -1 gd7 ->  1  0 -1 -2  -3  -4 6  }t
\ t{    4  1   0 gd7 ->  1  1  1  1   1   1 6  }t
\ t{    0  0   0 gd7 ->  0  0  0  0   0   0 6  }t
\ t{    1  4   0 gd7 ->  4  4  4  4   4   4 6  }t
\ t{    1  4   1 gd7 ->  4  5  6  7   8   9 6  }t
\ t{    4  1   1 gd7 ->  1  2  3            3  }t
\ t{    4  4   1 gd7 ->  4  5  6  7   8   9 6  }t
\ t{    2 -1  -1 gd7 -> -1 -2 -3 -4  -5  -6 6  }t
\ t{   -1  2  -1 gd7 ->  2  1  0 -1         4  }t
\ t{    2 -1   0 gd7 -> -1 -1 -1 -1  -1  -1 6  }t
\ t{   -1  2   0 gd7 ->  2  2  2  2   2   2 6  }t
\ t{   -1  2   1 gd7 ->  2  3  4  5   6   7 6  }t
\ t{    2 -1   1 gd7 -> -1 0 1              3  }t
\ t{  -20 30 -10 gd7 -> 30 20 10  0 -10 -20 6  }t
\ t{  -20 31 -10 gd7 -> 31 21 11  1  -9 -19 6  }t
\ t{  -20 29 -10 gd7 -> 29 19  9 -1 -11     5  }t

.\ F.6.1.1730	j
\ TODO: [loop] MTN - Some of these fail because my current implementation of +loop doesn't work with
\ negative increments
t{ : gd3 do 1 0 do j loop loop ; ->               }t
t{          4        1 gd3 -> 1 2 3               }t
\ t{          2       -1 gd3 -> -1 0 1              }t
t{ mid-uint+1 mid-uint gd3 -> mid-uint            }t
\ t{ : gd4 do 1 0 do j loop -1 +loop ; ->           }t
\ t{        1          4 gd4 -> 4 3 2 1             }t
\ t{       -1          2 gd4 -> 2 1 0 -1            }t
\ t{ mid-uint mid-uint+1 gd4 -> mid-uint+1 mid-uint }t

.\ F.6.1.1760	leave
\ TODO: [loop] MTN - not implemented, but should be
\ t{ : gd5 123 swap 0 do i 4 > if drop 234 leave then loop ; -> }t
\ t{ 1 gd5 -> 123 }t
\ t{ 5 gd5 -> 123 }t
\ t{ 6 gd5 -> 234 }t

.\ F.6.1.2380	unloop
t{ : gd6 0 swap 0 do
           i 1+ 0 do
             i j + 3 = if i unloop i unloop exit then 1+
           loop
         loop ; -> }t
t{ 1 gd6 -> 1 }t
t{ 2 gd6 -> 3 }t
t{ 3 gd6 -> 4 1 2 }t

.\ F.3.16		Defining Words
.\ F.6.1.0450	:
t{ : nop : postpone ; ; -> }t
t{ nop nop1 nop nop2 -> }t
t{ nop1 -> }t
t{ nop2 -> }t

t{ : gdx 123 ; : gdx gdx 234 ; -> }t
t{ gdx -> 123 234 }t

.\ F.6.1.0950	constant
t{ 123 constant x123 ->     }t
t{ x123              -> 123 }t
t{ : equ constant ;  ->     }t
t{ x123 equ y123     ->     }t
t{ y123              -> 123 }t

.\ F.6.1.2410	variable
t{ variable v1 ->     }t
t{ 123 v1 !    ->     }t
t{ v1 @        -> 123 }t

.\ F.6.1.1250	does> and create
t{ : does1 does> @ 1 + ; -> }t
t{ : does2 does> @ 2 + ; -> }t
t{ create cr1 -> }t
t{ cr1   -> here }t
t{ 1 ,   ->   }t
t{ cr1 @ -> 1 }t
t{ does1 ->   }t
t{ cr1   -> 2 }t
t{ does2 ->   }t
t{ cr1   -> 3 }t
t{ : weird: create does> 1 + does> 2 + ; -> }t
t{ weird: w1 -> }t
t{ ' w1 >body -> here }t
t{ w1 -> here 1 + }t
t{ w1 -> here 2 + }t

.\ F.6.1.0550	>body and create
t{  create cr0 ->      }t
t{ ' cr0 >body -> here }t

.\ F.3.17		Evaluate
.\ F.6.1.1360	evaluate

\ TODO: [evaluate] MTN - these fail right now because our evaluate requires a net zero stack effect
\ from the thing evaluated

\ : ge1 s" 123" ; immediate
\ : ge2 s" 123 1+" ; immediate
\ : ge3 s" : ge4 345 ;" ;
\ : ge5 evaluate ; immediate
\ t{ ge1 evaluate -> 123 }t       ( test evaluate in interp. state )
\ t{ ge2 evaluate -> 124 }t
\ t{ ge3 evaluate ->     }t
\ t{ ge4          -> 345 }t
\ t{ : ge6 ge1 ge5 ; ->  }t       ( test evaluate in compile state )
\ t{ ge6 -> 123 }t
\ t{ : ge7 ge2 ge5 ; ->  }t
\ t{ ge7 -> 124 }t

.\ F.3.18		Parser Input Source Control
.\ F.6.1.2216	source
\ TODO: [evaluate] MTN - these fail with a stack mismatch with the nested evaluate

\ : gs1 s" source" 2dup evaluate >r swap >r = r> r> = ;
\ t{ gs1 -> <true> <true> }t
\ : gs4 source >in ! drop ;
\ t{ gs4 123 456 -> }t

.\ F.6.1.0560	>in
\ TODO: [evaluate] MTN - these fail because of how we handle input during evaluate. In our evaluate,
\ source and >in cover the entire buffer being evaluated. It looks like the standard behavior is to
\ take it line-by-line as with `refill` in the usual definition of `quit`.

\ variable scans
\ : rescan? -1 scans +! scans @ if 0 >in ! then ;
\ t{ 2 scans ! 345 rescan? -> 345 345 }t


.\ F.6.1.2450	word
\ TODO: [wordfind] MTN - these fail because our `word` returns ( caddr u ) instead of a counted
\ string
\ : gs3 word count swap c@ ;
\ t{ bl gs3 hello -> 5 char h }t
\ t{ char " gs3 goodbye" -> 7 char g }t
\ t{ bl gs3 drop -> 0 }t \ blank lines return zero-length strings

.\ F.3.19		Number Patterns
: s= ( addr1 c1 addr2 c2 -- flag )
  >r swap r@ = if               ( check for same length )
    r> ?dup if                  ( check not empty )
      0 do
        over c@ over c@ - if 2drop <false> unloop exit then
        swap char+ swap char+
      loop
    then
    2drop <true>                ( completed loop, strings match )
  else
    r> drop 2drop <false>       ( lengths unequal )
  then
;

( determine log2 of largest double )
24 constant max-base           ( base 2 ... 36 )
: count-bits 0 0 invert begin dup while >r 1+ r> 2* repeat drop ;
count-bits 2* constant #bits-ud

.\ F.6.1.1670	hold
\ TODO: [numpat] MTN - number patterns are not implemented yet
\ : gp1 <# 41 hold 42 0 0 #> s" BA" s= ;
\ t{ gp1 -> <true> }t

.\ F.6.1.2210	sign
\ TODO: [numpat] MTN - number patterns are not implemented yet
\ : gp2 <# -1 sign 0 sign -1 sign 0 0 #> s" --" s= ;
\ t{ gp2 -> <true> }t

.\ F.6.1.0030	<# # #>
\ TODO: [numpat] MTN - number patterns are not implemented yet
\ : gp3 <# 1 0 # # #> s" 01" s= ;
\ t{ gp3 -> <true> }t

.\ F.6.1.0570	>number
\ TODO: [numpat] MTN - number patterns are not implemented yet
\ create gn-buf 0 c,
\ : gn-string gn-buf 1 ;
\ : gn-consumed gn-buf char+ 0 ;
\ : gn' [char] ' word char+ c@ gn-buf c! gn-string ;
\
\ t{ 0 0 gn' 0' >number ->         0 0 gn-consumed }t
\ t{ 0 0 gn' 1' >number ->         1 0 gn-consumed }t
\ t{ 1 0 gn' 1' >number -> base @ 1+ 0 gn-consumed }t
\ \ following should fail to convert
\ t{ 0 0 gn' -' >number ->         0 0 gn-string   }t
\ t{ 0 0 gn' +' >number ->         0 0 gn-string   }t
\ t{ 0 0 gn' .' >number ->         0 0 gn-string   }t
\
\ : >number-based base @ >r base ! >number r> base ! ;
\
\ t{ 0 0 gn' 2'       10 >number-based ->  2 0 gn-consumed }t
\ t{ 0 0 gn' 2'        2 >number-based ->  0 0 gn-string   }t
\ t{ 0 0 gn' f'       10 >number-based ->  f 0 gn-consumed }t
\ t{ 0 0 gn' g'       10 >number-based ->  0 0 gn-string   }t
\ t{ 0 0 gn' g' max-base >number-based -> 10 0 gn-consumed }t
\ t{ 0 0 gn' z' max-base >number-based -> 23 0 gn-consumed }t
\
\ : gn1 ( ud base -- ud' len )
\    \ ud should equal ud' and len should be zero.
\    base @ >r base !
\    <# #s #>
\    0 0 2swap >number swap drop    \ return length only
\    r> base ! ;
\
\ t{        0   0        2 gn1 ->        0   0 0 }t
\ t{ max-uint   0        2 gn1 -> max-uint   0 0 }t
\ t{ max-uint dup        2 gn1 -> max-uint dup 0 }t
\ t{        0   0 max-base gn1 ->        0   0 0 }t
\ t{ max-uint   0 max-base gn1 -> max-uint   0 0 }t
\ t{ max-uint dup max-base gn1 -> max-uint dup 0 }t

.\ F.6.1.0750	base
: gn2 base @ >r hex base @ decimal base @ r> base ! ;
t{ gn2 -> 10 a }t

.\ F.3.20		Memory Movement
create fbuf 00 c, 00 c, 00 c,
create sbuf 12 c, 34 c, 56 c,
: seebuf fbuf c@ fbuf char+ c@ fbuf char+ char+ c@ ;
.\ F.6.1.1540	fill
t{ fbuf 0 20 fill ->          }t
t{ seebuf         -> 00 00 00 }t
t{ fbuf 1 20 fill ->          }t
t{ seebuf         -> 20 00 00 }t
t{ fbuf 3 20 fill ->          }t
t{ seebuf         -> 20 20 20 }t

.\ F.6.1.1900	move
\ TODO: [nomove] MTN - move not implemented
\ t{ fbuf fbuf 3 chars move       ->          }t
\ t{ seebuf                       -> 20 20 20 }t
\ t{ sbuf fbuf 0 chars move       ->          }t
\ t{ seebuf                       -> 20 20 20 }t
\ t{ sbuf fbuf 1 chars move       ->          }t
\ t{ seebuf                       -> 12 20 20 }t
\ t{ sbuf fbuf 3 chars move       ->          }t
\ t{ seebuf                       -> 12 34 56 }t
\ t{ fbuf fbuf char+ 2 chars move ->          }t
\ t{ seebuf                       -> 12 12 34 }t
\ t{ fbuf char+ fbuf 2 chars move ->          }t
\ t{ seebuf                       -> 12 34 34 }t

.\ F.3.21		Output
.\ F.6.1.1320	emit
\ TODO: [negprint] MTN - printing negative numbers is broken for some reason. The last two output
\ lines will not be right.
: output-test
  ." You should see the standard graphic characters:" cr
  41 bl do i emit loop cr
  61 41 do i emit loop cr
  7f 61 do i emit loop cr
  ." You should see 0-9 separated by a space:" cr
  9 1+ 0 do i . loop cr
  ." You should see 0-9 (with no spaces):" cr
  [char] 9 1+ [char] 0 do i 0 spaces emit loop cr
  ." You should see A-G separated by a space:" cr
  [char] G 1+ [char] A do i emit space loop cr
  ." You should see 0-5 separated by two spaces:" cr
  5 1+ 0 do i [char] 0 + emit 2 spaces loop cr
  ." You should see two separate lines:" cr
  s" Line 1" tell cr s" Line 2" tell cr
  ." You should see the number ranges of signed and unsigned numbers:" cr
  ." Signed: " min-int . max-int . cr
  ." Unsigned:" 0 u. max-uint u. cr
;
t{ output-test -> }t

.\ F.3.22		Input
.\ F.6.1.0695	accept


cr
