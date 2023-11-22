# Design and Implementation

## Software Model

1. The USB subsystem is generic. It is found under `/usb.zig`. It provides an API for a Class Driver.
1. At least two classes will be needed, a HID mouse and a HID keyboard.
1. A Class Driver may be synchronous or asynchronous. How an application communicates with a Class Driver is TBD.
1. The USB host controller is hardware-specific. It is found under `/drivers`. For Raspberry Pi3, it is `/drivers/dwc_otg_usb.zig`.
1. A USB Device is generic. It is found under `/usb/device.zig`.
1. A Device has at least one Endpoint.
1. A USB Endpoint is generic. It is found under `/usb/endpoint.zig`
1. A USB Request is generic. It is found under `/usb/request.zig`
1. The generic structs have references to hardware-specific structs and functions supplied by the host controller driver. These are comptime resolved via type aliases in HAL.
2. Class Drivers should work at the level of Requests and Endpoints. A Class Driver should construct a Request and hand it off to the host controller.
1. A Request must be performed by the host controller.
1. The host controller turns a Request into one or more Transfers. 
   1. Each Transfer comprises multiple Transactions. 
   1. Transactions in a Transfer are grouped into Stages.
   2. Each Transaction comprises one or more Packets.
      1. For Transactions in the Setup stage: One Transaction with one Token Packet.
      2. For Transactions in the Data stage: Zero or more Transactions, which each have a Setup packet, zero or more Data packets, and a Status packet.
      2. For Transactions in the Status stage: One Transaction with a Setup packet, zero or more Data packets, and a Status packet.
   1. Each packet has a Packet ID (PID) from the table below.
1. Every Transaction in a Transfer has the same device address and endpoint number as the Transfer.
   1. A Stage has a direction (either host-to-device or device-to-host).
   1. A Stage may have multiple Packets.
1. A Control Transfer comprises the following Stages
   2. Setup stage: a Setup Transaction
   3. Data stage: zero or more Data Transactions
   4. Status stage: a Status Transaction
1. The host controller has multiple Channels. These have no independent representation and are strictly contained within the host controller driver (HCD).
1. A Transfer is performed on a Channel. The HCD runs an interrupt-driven state machine to execute the Transfer on a Channel.

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

