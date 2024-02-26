Another example, well commented: https://github.com/LdB-ECM/Raspberry-Pi/blob/master/SD_FAT32/SDCard.c

From  https://www.prodigytechno.com/emmc-protocol/

Name	Register 
        Width
        (byte)	Description

CID	    16	    Device Identification Number

RCA	    2	    Relative Device Address, is the Device system Address, dynamically assigned by the host during initialization

DSR	    2	    Driver State Register (Optional)

CSD	    16	    Device Specific Data, information about the device operation Condition

OCR	    4	    Operation Conditions Register. Used by the special broadcast command to identify the voltage type of the device

EXT_CSD	512	    Extended Device Specific Data. Contains information about the device’s capabilities and selected modes.


There are 64 emmc commands, cmd0 thru cmd63.

Command token is 48 bits wide.

* 1 bit   - start bit, always 0.
* 1 bit   - host command (presumably a flag), always 1
* 6 bits  - cmd type, some are reserved.
* 32 bits - 32 bit argument
* 7 bits  - crc -- handled by the pi (I think)
* 1 bit   - end bit, always 1.


Response token is either 48 or 136  bits wide.
The R1, R3, R4 and R5 responses are 48 bits:

* 1 bit   - start bit, always 0.
* 1 bit   - response (presumably a flag), always 0
* 38 bits - content
* 7 bits  - crc -- handled by the pi (I think)
* 1 bit   - end bit, always 1.

R5 has the 136 bit wide address:

* 1 bit   - start bit, always 0.
* 1 bit   - response (presumably a flag), always 0
* 126 bits - content, CID or CSD (16ish bytes, 4ish 32bit words)
* 7 bits  - crc -- handled by the pi (I think)
* 1 bit   - end bit, always 1.

R5 has either the CID (dev info number) or CSD (dev specific data).



R1 has the card status information.

R3 has the OCR register. Condition of the card.

R4 and R5?? have the relative card address. 


There are also data tokens that can run in either direction.
Data can be transfered in 1 line or 4 lines or 8 lines.
Dat0 is for 1 line, Dat0-Dat3 is four lines and Dat0-Dat7 for 
8 lines.


== From https://www.nexpcb.com/blog/emmc-flash-chips-explained

OCR: The 32-bit operation conditions register stores the voltage profile of the card, the access mode indication. the busy flag, etc.

CID: The 128-bit card identification register contains the identification information of the device. Each device has a unique identification number.

CSD: The 128-bit card-specific data register contains information about accessing the device contents. The CSD register defines the data format, error correction type, maximum data access time, and data transfer speed, etc.

CSD: The 4096-byte extended card-specific data register defines device properties and selection modes. The upper 320 bytes make the property segment. This segment defines device capabilities and cannot be modified by the host. The lower 192 bytes make the mode field. The mode field defines the configuration in which the device is working. The host revises the mode field with the SWITCH command.

CA: The 16-bit relative device address register stores the device address assigned by the host.

SR: The 16-bit drive level re


== Another good example: https://github.com/jncronin/rpi-boot/blob/master/emmc.c


From  https://forums.raspberrypi.com/viewtopic.php?t=59395

In particular the diagram on page 20 which shows the states and commands.

One thing to note is that the EMMC interface in the Pi automatically takes care of CRCs, so you don't ever explicitly include those in the commands. Another is to note that small delays are needed between setting the registers and checking for the outcome of that action - for the initial reset I wait 10 microseconds after each change to the CONTROL registers, might be overkill.

The two critical elements in getting this all working are the reset+setting of the clock and the sending of commands - and then following the startup sequence in the document. It's hard to give an outline without going into huge amounts of detail, but FWIW for the reset/clock setting:

* Set CONTROL0 and CONTROL2 to 0
* Set CONTROL1 to 0x01000000 (reset host controller circuit)
* Wait until that flag clears in CONTROL1
* Or CONTROL1 with 0x000e0001 (C1_CLK_INTLEN and C1_TOUNIT_MAX )
* Set clock frequency to 400Khz (disable the clock (turn off 0x00000004 in CONTROL1), OR the appropriate divider value into CONTROL1, enable the clock by turning 0x00000004 on again)
* Wait for clock stable flag (0x00000002)
* Enable all interrupts (IRPT_EN = 0xffffffff, IRPT_MASK = 0xffffffff)
* Perform the initialization command sequence - setting the clock frequency to normal (25Mhz) after getting the card's CSD.

The individual command sequence is:

* Clear interrupt flag
* Set ARG1 flag to the argument value for the command, if any
* Set CMDTM to the command value, a 32-bit value with the command index in the high 8 bits
* Wait for COMMAND_DONE interrupt (or error)
* Parse response according to the type of command

```
typedef struct EMMCCommand
  {
  const char* name;
  unsigned int code;
  unsigned char resp;
  unsigned char rca;
  int delay;
  } EMMCCommand;

// Command table.
static EMMCCommand sdCommandTable[] =
  {
  { "GO_IDLE_STATE", 0x00000000|CMD_RSPNS_NO                             , RESP_NO , RCA_NO  ,0},
  { "ALL_SEND_CID" , 0x02000000|CMD_RSPNS_136                            , RESP_R2I, RCA_NO  ,0},
  { "SEND_REL_ADDR", 0x03000000|CMD_RSPNS_48                             , RESP_R6 , RCA_NO  ,0},
  { "SET_DSR"      , 0x04000000|CMD_RSPNS_NO                             , RESP_NO , RCA_NO  ,0},
  { "SWITCH_FUNC"  , 0x06000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "CARD_SELECT"  , 0x07000000|CMD_RSPNS_48B                            , RESP_R1b, RCA_YES ,0},
  { "SEND_IF_COND" , 0x08000000|CMD_RSPNS_48                             , RESP_R7 , RCA_NO  ,100},
  { "SEND_CSD"     , 0x09000000|CMD_RSPNS_136                            , RESP_R2S, RCA_YES ,0},
  { "SEND_CID"     , 0x0A000000|CMD_RSPNS_136                            , RESP_R2I, RCA_YES ,0},
  { "VOLT_SWITCH"  , 0x0B000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "STOP_TRANS"   , 0x0C000000|CMD_RSPNS_48B                            , RESP_R1b, RCA_NO  ,0},
  { "SEND_STATUS"  , 0x0D000000|CMD_RSPNS_48                             , RESP_R1 , RCA_YES ,0},
  { "GO_INACTIVE"  , 0x0F000000|CMD_RSPNS_NO                             , RESP_NO , RCA_YES ,0},
  { "SET_BLOCKLEN" , 0x10000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "READ_SINGLE"  , 0x11000000|CMD_RSPNS_48 |CMD_IS_DATA  |TM_DAT_DIR_CH, RESP_R1 , RCA_NO  ,0},
  { "READ_MULTI"   , 0x12000000|CMD_RSPNS_48 |TM_MULTI_DATA|TM_DAT_DIR_CH, RESP_R1 , RCA_NO  ,0},
  { "SEND_TUNING"  , 0x13000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "SPEED_CLASS"  , 0x14000000|CMD_RSPNS_48B                            , RESP_R1b, RCA_NO  ,0},
  { "SET_BLOCKCNT" , 0x17000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "WRITE_SINGLE" , 0x18000000|CMD_RSPNS_48 |CMD_IS_DATA  |TM_DAT_DIR_HC, RESP_R1 , RCA_NO  ,0},
  { "WRITE_MULTI"  , 0x19000000|CMD_RSPNS_48 |TM_MULTI_DATA|TM_DAT_DIR_HC, RESP_R1 , RCA_NO  ,0},
  { "PROGRAM_CSD"  , 0x1B000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "SET_WRITE_PR" , 0x1C000000|CMD_RSPNS_48B                            , RESP_R1b, RCA_NO  ,0},
  { "CLR_WRITE_PR" , 0x1D000000|CMD_RSPNS_48B                            , RESP_R1b, RCA_NO  ,0},
  { "SND_WRITE_PR" , 0x1E000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "ERASE_WR_ST"  , 0x20000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "ERASE_WR_END" , 0x21000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "ERASE"        , 0x26000000|CMD_RSPNS_48B                            , RESP_R1b, RCA_NO  ,0},
  { "LOCK_UNLOCK"  , 0x2A000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "APP_CMD"      , 0x37000000|CMD_RSPNS_NO                             , RESP_NO , RCA_NO  ,100},
  { "APP_CMD"      , 0x37000000|CMD_RSPNS_48                             , RESP_R1 , RCA_YES ,0},
  { "GEN_CMD"      , 0x38000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},

  // APP commands must be prefixed by an APP_CMD.
  { "SET_BUS_WIDTH", 0x06000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "SD_STATUS"    , 0x0D000000|CMD_RSPNS_48                             , RESP_R1 , RCA_YES ,0}, // RCA???
  { "SEND_NUM_WRBL", 0x16000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "SEND_NUM_ERS" , 0x17000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "SD_SENDOPCOND", 0x29000000|CMD_RSPNS_48                             , RESP_R3 , RCA_NO  ,1000},
  { "SET_CLR_DET"  , 0x2A000000|CMD_RSPNS_48                             , RESP_R1 , RCA_NO  ,0},
  { "SEND_SCR"     , 0x33000000|CMD_RSPNS_48|CMD_IS_DATA|TM_DAT_DIR_CH   , RESP_R1 , RCA_NO  ,0},
  };

static int sdSendCommand( int index )
  { // ... get cmd from table; check if APP_CMD is needed, sends that if so.
    // checks cmd->rca and if set uses card's rca as the arg value, then calls sdSendCommandP(cmd,arg); }

static int sdSendCommand( int index, int arg )
  { // ... get cmd from table; check if APP_CMD is needed, sends that if so.
    // calls sdSendCommandP(cmd,arg); }

static int sdSendCommandP( EMMCCommand* cmd, int arg )
  {
  // Clear interrupt flags.  This is done by setting the ones that are currently set.
  *EMMC_INTERRUPT = *EMMC_INTERRUPT;

  // Set the argument and the command code.
  // Some commands require a delay before reading the response.
  *EMMC_ARG1 = arg;
  *EMMC_CMDTM = cmd->code;
  if( cmd->delay ) waitMicro(cmd->delay);

  // Wait until command complete interrupt.
  if( (result = sdWaitForInterrupt(INT_CMD_DONE)) ) return result;

  // Get response from RESP0.
  int resp0 = *EMMC_RESP0;

  // Handle response types.
  switch( cmd->resp )
    {
    // No response.
    case RESP_NO:

   ...etc...
```


Relatively clean, public domain example along these lines here:
https://github.com/moizumi99/RPiHaribote/blob/master/haribote/sdcard.c


SDCard Registers (From https://www.utmel.com/blog/categories/memory%20chip/an-overview-of-sd-card)

 * OCR (OPERATING CONDitions Register): 32-bit operating condition register mainly stores the VDD voltage range, and the SD card operating voltage range is 2 ~ 3.6V. 
 * 
 * CID (CARD Identification Register) Register: The card identification code register, the length is 16 bytes, and the SD card unique identification number is stored. This number cannot be modified after the card manufacturer is programmed. 
 * 
 * CSD (Card-Specific Data Register) Register: The Carter Data Register contains the necessary configuration information when accessing the card data.
 * 
 * SCR (SD CARD Configuration Register): SD Card Configuration Register (SCR) provides some special features with the SD card which are 64 bits, and this register content is set by the manufacturer. 
 * 
 * RCA (Relative Card Address) Register: The card relative address register is a 16-bit writable address register. The controller can select the SD card corresponding to the address by the address.
 * 
 * DSR (Driver Stage Register) Register: Drive Level Register, which belongs to an optional register for configuring the drive output.
