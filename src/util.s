.global spin_delay
spin_delay:
    subs x0, x0, #1
    bne spin_delay
    ret