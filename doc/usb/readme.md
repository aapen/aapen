# Design and Implementation

## Limitations

We currently do not handle:

  - Split transfers
  - Isochronous transfers
  - Periodic transfers

## Software Model

1. The USB subsystem is generic. It is found under `/usb.zig`. It provides an API for a Class Driver.
2. At least three classes will be needed: Hub, HID mouse, and HID keyboard.
3. A Class Driver may be synchronous or asynchronous. How an application communicates with a Class Driver is TBD.
4. The USB host controller driver (HCD) is hardware-specific. It is found under `/drivers`. For Raspberry Pi3, it is `/drivers/dwc_otg_usb.zig`.
5. A USB Device is generic. It is found in `/usb/device.zig`.
6. A Device has at least one Endpoint.
7. An Endpoint is generic. An Endpoint is described in a device configuration but does not get reified.
8. A USB Transfer Request is generic. It is found under `/usb/transfer.zig`
9. A Transfer Request describes the application's desired action. It also contains stateful "bookkeeping" information used by the core and the HCD.
10. Class Drivers work at the level of Requests and Devices.
11. An application or a class driver can submit a Transfer Request to the core. The core delegates it to the HCD.
12. The host controller processes Transfer Requests on a background thread.
   1. Each Transfer comprises multiple Transactions. It is the job of the HCD to schedule and initiate the Transactions. The HC hardware handles all Packet-level interaction.
   2. For a Control Transfer, there are either two or three stages. Each stage is a separate Transaction. The HCD must keep track of the stages in the Control Transfer. (See [USB 2.0 Specification](https://www.usb.org/document-library/usb-20-specification) sections 5.5 and 9.3.)
      1. In the Setup stage, the HCD sends the "setup data".
      2. In the Data stage, the HCD either sends or receives the payload. It the transfer size is bigger than the endpoint's "max packet size", this will require the HCD to initiate multiple transactions. If the control transfer is a type that doesn't have any data, this stage is skipped.
      3. In the Status stage, the HCD either sends or receives a handshake transaction. (The direction depends on the direction of the data stage.)
   3. The HCD assigns the initial Packet ID (PID) on the first transaction in each stage. The HCD is required to toggle the PID between DATA1/DATA0 on each alternate transaction in a data stage.
13. Every Transaction in a Transfer has the same device address and endpoint number as the Transfer.
14. The host controller has multiple Channels. These have no independent representation and are strictly contained within the host controller driver.
15. A Transfer is performed on a Channel. The HCD runs an interrupt-driven state machine to execute the Transfer on a Channel.

## Subsystem initialization

1. The OS calls the `usb.initialize`.
2. `usb.initialize` registers all class drivers compiled into the kernel.
3. `usb.initialize` tells the HCD to initialize.
4. The HCD verifies that it is the right driver for the hardware, then initializes the chip.
   1. This includes setting up control registers, initializing the interrupt mask, and starting the background thread that will process Transfer Requests.
5. The core allocates a device address (should be 1 at this point!) and attaches the Root Hub as device 1.
   1. Attaching the device starts the "device initialization" process for the Root Hub.

## Device initialization

When a device is connected (or detected on power-up scan) we have to take multiple steps before it is ready for use:

1. Device is initially detected with device address zero. Its function is unknown. Its maximum packet size is unknown.
   1.  Perform a control transfer to device address 0 and request `get_descriptor` with decscriptor type `device` but fixed length of 8. Read the device class, subclass, protocol, max packet size.
   2. If this is not the root hub, get the hub & port this device is being attached to, and send a `port reset` to that hub.
   3. Pick an unused device address (call it A1) to assign to the new device. Perform a control transfer to the device address 0, endpoint 0 with a `set_address` request.
2. Device now has an assigned address. Its function is still unknown.
   1. Perform a control transfer to device address A1 to read the whole device descriptor.
   2. Perform a control transfer to A1 to get the Configuration descriptor.
   3. Perform a control transfer to A1 to set the selected configuration to the first offered configuration.
   4. Attempt to locate a driver that can support the device.
      1. Iterate registered drivers, asking each if it can bind the device.
      2. If a driver can bind the device, tell it to do so. This initiates the "Xxx class driver bind" process.

## Hub class driver bind

1. Confirm the device is actually a hub, by examining its class and confirming the first endpoint is an interrupt endpoint (USB spec requires this for all hubs.)
2. Read the hub descriptor, determine the port count.
3. Initialize ports and power them on.
4. Send an interrupt request to the interrupt endpoint. This will report future status changes.

## Hub class driver status change

1. When an interrupt transfer finishes:
   1. If the transfer was successful, flag that this hub has a pending change and signal the hub thread semaphore.
2. On the hub thread (which services all hubs), wait on the semaphore. When it is signalled:
   1. For each hub that has a status change
      1. For each port that has a status change,
         1. Get the port's status (this is a control transfer)
         2. Set the port's "clear" feature bit for whatever changes have been observed.
            (Note: this is a bit confusing. There is a feature "C_" for each status bit. E.g., `C_PORT_ENABLE` is the feature to clear the port enable flag. We must _set_ this feature to _clear_ the flag. It does no good to _clear_ the `PORT_ENABLE` feature.)
         3. If the status indicated a `connected_changed` bit:
            1. If there was previously a device attached to this port, unbind it's driver and detach the device.
            2. If there is now a device attached to this port, begin the "Device initialization" process.

## HID Keyboard class driver bind

1. Confirm the device is actually a keyboard, by examining its interface and endpoint.
2. Find which endpoint is the "interrupt in" endpoint
3. Send a control transfer to set the protocol of that interface to use the "HID boot" protocol

## Hardware Model - RPi3

1. The DWC OTG USB host controller (HC) operates at the level of USB Transactions.
2. A Transaction is handled by a channel.
3. The HC has a set of registers for each channel (out of the 15 channels supported on the chip.)
4. It's up to the application (our operating system) to keep track of which channels are busy.
5. The application (our operating system) sets up a description of the transaction:
   1. Configure the `channel_transfer_size` register, with both the number of packets and the number of bytes.)
   2. The `channel_transfer_size` register is also where the initial PID goes. (I.e., `SETUP`, `DATA0`, etc.) It seems that the host controller updates each successive packet's PID.
   3. Configure the `channel_dma_addr` to point at the data to be sent or where the data will be received.
   4. Configure the `channel_int_mask` according to the expected interrupts.
   5. Configure the `channel_character` with the endpoint number, direction, address, "odd frame" bit, low-speed device bit, disable flag (set to 0), and enable flag (set to 1).
6. It's up to the application to handle NAK, NYET, Stall, and error interrupts.
7. During the transaction, the HCD will update the transfer size and `channel_dma_buffer` address (I think this means `channel_dma_addr` stays the same)
8. A "split" transfer deals with low speed devices on a full- or high-speed bus. There's a lot I don't understand about split transfers, so I hope that we don't actually need to deal with them for the keyboard and mouse.

## Packet IDs (PIDs)

```
Group   Value   Packet Identifier
Token
        0001    OUT
        1001    IN 
        0101    SOF
        1101    SETUP
Data
        0011    DATA0
        1011    DATA1
        0111    DATA2
        1111    MDATA
Handshake
        0010    ACK Handshake
        1010    NAK Handshake
        1110    STALL Handshake
        0110    NYET (No Response Yet)
Special
        1100    PREamble
        1100    ERR
        1000    Split
        0100    Ping
```

## Device State Machine

![](device_state_machine.png)

## Transfer Logical Model

This is meant to depict the relationships of the actions. Not all of these are reified as structures.

![](transfer_model.png)

# References

[Universal Serial Bus Specification, Revision 2.0](https://www.usb.org/document-library/usb-20-specification)

[RiscOS implementation of DWC driver](https://gitlab.riscosopen.org/RiscOS/Sources/HWSupport/USB/Controllers/DWCDriver/-/tree/master)

[MSDN article about enumerating devices](https://techcommunity.microsoft.com/t5/microsoft-usb-blog/how-does-usb-stack-enumerate-a-device/ba-p/270685)
