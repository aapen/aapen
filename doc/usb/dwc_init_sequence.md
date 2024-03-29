# DWC OTG USB init sequence

1.  check vendor ID register (confirms the USB device exists)
2.  power on (via mailbox message to power controller)
3.  disable interrupts
    1.  `core_ahb_config &= ~(GLOBAL_INTERRUPT_MASK)`
4.  connect IRQ handler
5.  initialize USB core
    1.  `core_usb_config &= ~(ULPI_EXT_VBUS_DRV | TERM_SEL_DL_PULSE)`
    2.  reset core
        1.  wait up to 100 ms for `core_reset & AHB_IDLE == 1`
        2.  `core_reset |= ~SOFT_RESET`
        3.  wait up to 10 ms for `core_reset & SOFT_RESET == 0`
        4.  wait 100 ms
    3.  select UTMI+ with width = 8
        `core_usb_config &= ~(ULPI_UTMI_SEL | CFG_PHYIF)`
    4.  ??
        1.  if `hw cfg2 hs_phy_type == phy_ulpi && fs_phy_type == phy_type_dedicated`
            1.  set bits `cfg_ulpi_fsls` and `cfg_ulpi_clk_sus_m` in `core_usb_config`
        2.  else
            1.  clear bits `cfg_ulpi_fsls` and `cfg_ulpi_clk_sus_m` in `core_usb_config`
    5.  get host channel count from `core_hardware_config_2`
    6.  Enable DMA
        1.  set bits `dmaenable` and `wait_axi_writes` in `core_ahb_config`, clear `max_axi_burst_mask`
    7.  disable HNP and SRP
        1.  Clear bits `hnp_capable` and `srp_capable` in `core_usb_config`
    8.  enable common interrupts
        1.  set all bits in `core_interrupt_status`
6.  enable global interrupts
    1.  set `global_int_mask` in `core_ahb_config`
7.  initialize host
    1.  write 0 to `usb_power` (`usb_base` + 0xe00)
    2.  clear bit `fsls_pclk_sel__mask` in `host_config`
    3.  if hwconfig2 says phy is ulpi and dedicated, and usb config says `ulpi_fsls`,
        (if `core_hardware_config_2 hs_phy_type == phy_ulpi *and* fs_phy_type == phy_type_dedicated` *and* `core_usb_config` has bit `cfg_ulpi_fsls` set)
        1.  then set `host_config`'s `fsls_pclk` selector to 48 mhz
        2.  otherwise
            1.  set bit `host_config`'s `fsls_pclk` to `30_60_mhz`
    4.  flush tx fifo 10
        1.  As one atomic write:
            1.  set `tx_fifo_flush` in `core_reset`
            2.  clear bits of `tx_fifo_num` in `core_reset`
            3.  set bits of `tx_fifo_num` with parameter (0x10)
        2.  Wait up to 10 ms for `tx_fifo_flush` bit in `core_reset` to return to 0
        3.  Wait 1 more microsecond
    5.  flush rx fifo
        1.  As one atomic write:
            1.  set bit `rx_fifo_flush` in `core_reset`
        2.  Wait up to 10 ms for `rx_fifo_flush` bit in `core_reset` to return to 0
        3.  Wait 1 more microsecond
    6.  if bit `host_port_power` is not set in `host_port`
        set bit `host_port_power`
    7.  enable host interrupts
        1.  disable all interrupts during the change (set `core_int_mask` to 0)
        2.  clear pending interrupts (set `core_int_stat` to all 1's)
        3.  set `hc_intr` bit in `core_int_mask`
8.  Scan devices
    1.  enable root port
        1.  Wait up to 510 ms for `port_connect` bit of `host_port` register to be set
        2.  Delay 100 ms
        3.  In one atomic write to `host_port`
            1.  Clear bits `connect_changed`, `enable`, `enable_changed`, `overcurrent_changed`
            2.  Set bit `reset`
        4.  Delay 50 ms
        5.  In one atomic write to `host_port`
            1.  Clear bits `connect_changed`, `enable`, `enable_changed`, `overcurrent_changed`
            2.  Clear bit `reset`
        6.  Delay 20 ms
    2.  initialize root port
        1.  get port speed (read from `host_port.speed`)
        2.  create a default device
            1.  initialize it
            2.  configure it (requires ability to send control messages)
        3.  check for overcurrent, if detected disable the root port
    3.  scan the root port

