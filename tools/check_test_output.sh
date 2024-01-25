#! /usr/bin/env bash
TESTNAME=$1

EXPECTED_OUTPUT=$(sed -n -e '/expected_output/,/end_expected_output/ { /expected_output/d; /end_expected_output/d; s/^\/\/ //; p; }' src/test/${TESTNAME}.zig)

ACTUAL_OUTPUT=$(cat actual_output)

if [ "${ACTUAL_OUTPUT}" != "${EXPECTED_OUTPUT}" ]; then
    echo "Output does not match expected output."
    echo "--- expected"
    echo ".${EXPECTED_OUTPUT}."
    echo "--- actual"
    echo ".${ACTUAL_OUTPUT}."
    exit 1
else
    exit 0
fi
