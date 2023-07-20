#! /bin/bash
echo $1 | entr -c zig test $1
