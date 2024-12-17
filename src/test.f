base @ value test-old-base
hex

(
  Test harness

  A utility for testing Forth words, with a long derivation:

  Aapen source derived from https://www.forth200x.org/tests/ttester.fs, which includes this
  attribution:

\ ttester is based on the original tester suite by Hayes:
\ From: John Hayes S1I
\ Subject: tester.fr
\ Date: Mon, 27 Nov 95 13:10:09 PST
\ (C) 1995 JOHNS HOPKINS UNIVERSITY / APPLIED PHYSICS LABORATORY
\ MAY BE DISTRIBUTED FREELY AS LONG AS THIS COPYRIGHT NOTICE REMAINS.
\ VERSION 1.1
\ All the subsequent changes have been placed in the public domain.
\ The primary changes from the original are the replacement of "{" by "T{"
\ and "}" by "}T" (to avoid conflicts with the uses of { for locals and }
\ for FSL arrays), modifications so that the stack is allowed to be non-empty
\ before T{, and extensions for the handling of floating point tests.
\ Code for testing equality of floating point values comes
\ from ftester.fs written by David N. Williams, based on the idea of
\ approximate equality in Dirk Zoller's float.4th.
\ Further revisions were provided by Anton Ertl, including the ability
\ to handle either integrated or separate floating point stacks.
\ Revision history and possibly newer versions can be found at
\ http://www.complang.tuwien.ac.at/cvsweb/cgi-bin/cvsweb/gforth/test/ttester.fs
\ Explanatory material and minor reformatting (no code changes) by
\ C. G. Montgomery March 2009, with helpful comments from David Williams
\ and Krishna Myneni.

  The basic usage takes the form `t{ <code> -> <expected stack> }t`. This executes <code> and
  compares the resulting stack contents with the <expected stack> values, and reports any
  discrepancy between the two sets of values.

  Examples:
  t{ 1 2 3 swap -> 1 3 2 }t \  outputs nothing
  t{ 1 2 3 swap -> 1 2 2 }t \  outputs "incorrect result: t{ 1 2 3 swap -> 1 2 2 }t"
  t{ 1 2 3 swap -> 1 2 }t   \  outputs "wrong number of results: t{ 1 2 3 swap -> 1 2 }t"

  The word `error` is vectored, so you can change its action as needed.

 )

variable actual-depth
variable actual-results 20 cells allot
variable start-depth

defer error

\ ( ... -- ) empties the stack
: empty-stack
  depth start-depth @ < if
    depth start-depth @ swap do 0 loop
  then
  depth start-depth @ > if
    depth start-depth @ do drop loop
  then
;

\ ( c-addr u -- ) display an error message
: error1
  tell ." :["                   \ error message
  >in 60 < if
    inbuf @ >in @ tell
  else
    inbuf @ >in @ + 60 - 60
  then
  tell ." ]" cr          \ show the line that caused the problem
  empty-stack                   \ throw away everything else
;

' error1 is error

\ ( -- ) record the pre-test depth
: t{
  depth start-depth !
;

\ ( ... -- ) record depth and contents of stack
: ->
  depth dup actual-depth !
  start-depth @ > if             \ if there is something on the stack
    depth start-depth @ - 0 do   \ save them
      actual-results i cells + !
    loop
  then
;

\ ( ... -- ) compare stack (expected) contents with saved (actual) contents
: }t
  depth actual-depth @ = if
    depth start-depth @ > if
      depth start-depth @ - 0 do
        actual-results i cells + @
        <> if s" incorrect result " error unloop exit then
      loop
    then
  else
    s" wrong number of results " error
  then
;

test-old-base base ! hide test-old-base
