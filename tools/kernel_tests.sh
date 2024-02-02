#! /usr/bin/env bash
TESTS="confirm_qemu console_output bcd atomic event root_hub stack string synchronize transfer_factory transfer"

FAILED=0

for t in $TESTS; do
    make kernel_test TESTNAME=${t}

    if [[ $? -ne 0 ]]; then
        FAILED=1
    fi
done

if [[ $FAILED -ne 0 ]]; then
    echo "*** TESTS FAILED"
    exit -1
else
    echo "+++ OK"
    exit 0
fi
