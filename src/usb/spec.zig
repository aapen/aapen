/// Constants and structures defined by the USB specifications

// ----------------------------------------------------------------------
// Type aliases
// ----------------------------------------------------------------------

// Binary-coded decimal
pub const BCD = u16;

// Assigned ID number
pub const ID = u16;
pub const DescriptorIndex = u8;
pub const DeviceAddress = u7;
pub const DeviceStatus = u16;
pub const EndpointNumber = u4;
pub const LangId = u16;
pub const PacketSize = u11;
pub const StringIndex = u8;
pub const TransferBytes = u19;
pub const TransferPackets = u10;

// ----------------------------------------------------------------------
// Specified values
// ----------------------------------------------------------------------
// zig fmt: off

// USB specification versions
pub const usb1_0                                       : BCD = 0x0100;
pub const usb1_1                                       : BCD = 0x0110;
pub const usb2_0                                       : BCD = 0x0200;
pub const usb2_1                                       : BCD = 0x0210;
pub const usb3_0                                       : BCD = 0x0300;
pub const usb3_1                                       : BCD = 0x0310;
pub const usb3_2                                       : BCD = 0x0320;

// Descriptor types
pub const USB_DESCRIPTOR_TYPE_UNKNOWN                  : u8 = 0x00;
pub const USB_DESCRIPTOR_TYPE_DEVICE                   : u8 = 0x01;
pub const USB_DESCRIPTOR_TYPE_CONFIGURATION            : u8 = 0x02;
pub const USB_DESCRIPTOR_TYPE_STRING                   : u8 = 0x03;
pub const USB_DESCRIPTOR_TYPE_INTERFACE                : u8 = 0x04;
pub const USB_DESCRIPTOR_TYPE_ENDPOINT                 : u8 = 0x05;
pub const USB_DESCRIPTOR_TYPE_HID                      : u8 = 0x21;
pub const USB_DESCRIPTOR_TYPE_CLASS_INTERFACE          : u8 = 0x24;
pub const USB_DESCRIPTOR_TYPE_CLASS_ENDPOINT           : u8 = 0x25;
pub const USB_DESCRIPTOR_TYPE_HUB                      : u8 = 0x29;

// Device classes
pub const USB_DEVICE_INTERFACE_SPECIFIC                : u8 = 0x00;
pub const USB_DEVICE_AUDIO                             : u8 = 0x01;
pub const USB_DEVICE_CDC_CONTROL                       : u8 = 0x02;
pub const USB_DEVICE_HID                               : u8 = 0x03;
pub const USB_DEVICE_PHYSICAL                          : u8 = 0x05;
pub const USB_DEVICE_IMAGE                             : u8 = 0x06;
pub const USB_DEVICE_PRINTER                           : u8 = 0x07;
pub const USB_DEVICE_MASS_STORAGE                      : u8 = 0x08;
pub const USB_DEVICE_HUB                               : u8 = 0x09;
pub const USB_DEVICE_CDC_DATA                          : u8 = 0x0a;
pub const USB_DEVICE_SMART_CARD                        : u8 = 0x0b;
pub const USB_DEVICE_CONTENT_SECURITY                  : u8 = 0x0d;
pub const USB_DEVICE_VIDEO                             : u8 = 0x0e;
pub const USB_DEVICE_PERSONAL_HEALTHCARE               : u8 = 0x0f;
pub const USB_DEVICE_AUDIO_VIDEO                       : u8 = 0x10;
pub const USB_DEVICE_BILLBOARD                         : u8 = 0x11;
pub const USB_DEVICE_TYPE_C_BRIDGE                     : u8 = 0x12;
pub const USB_DEVICE_BULK_DISPLAY                      : u8 = 0x13;
pub const USB_DEVICE_MCTP_OVER_USB                     : u8 = 0x14;
pub const USB_DEVICE_I3C                               : u8 = 0x3c;
pub const USB_DEVICE_DIAGNOSTIC                        : u8 = 0xdc;
pub const USB_DEVICE_WIRELESS_CONTROLLER               : u8 = 0xe0;
pub const USB_DEVICE_MISCELLANEOUS                     : u8 = 0xef;
pub const USB_DEVICE_APPLICATION_SPECIFIC              : u8 = 0xfe;
pub const USB_DEVICE_VENDOR_SPECIFIC                   : u8 = 0xff;

// Endpoint directions
pub const USB_ENDPOINT_DIRECTION_OUT                   : u1 = 0b0;
pub const USB_ENDPOINT_DIRECTION_IN                    : u1 = 0b1;

// Standard request codes
pub const USB_REQUEST_GET_STATUS                       : u8 = 0x00;
pub const USB_REQUEST_CLEAR_FEATURE                    : u8 = 0x01;
pub const USB_REQUEST_SET_FEATURE                      : u8 = 0x03;
pub const USB_REQUEST_SET_ADDRESS                      : u8 = 0x05;
pub const USB_REQUEST_GET_DESCRIPTOR                   : u8 = 0x06;
pub const USB_REQUEST_SET_DESCRIPTOR                   : u8 = 0x07;
pub const USB_REQUEST_GET_CONFIGURATION                : u8 = 0x08;
pub const USB_REQUEST_SET_CONFIGURATION                : u8 = 0x09;
pub const USB_REQUEST_GET_INTERFACE                    : u8 = 0x0A;
pub const USB_REQUEST_SET_INTERFACE                    : u8 = 0x0B;
pub const USB_REQUEST_SYNCH_FRAME                      : u8 = 0x0C;
pub const USB_REQUEST_SET_ENCRYPTION                   : u8 = 0x0D;
pub const USB_REQUEST_GET_ENCRYPTION                   : u8 = 0x0E;
pub const USB_REQUEST_RPIPE_ABORT                      : u8 = 0x0E;
pub const USB_REQUEST_SET_HANDSHAKE                    : u8 = 0x0F;
pub const USB_REQUEST_RPIPE_RESET                      : u8 = 0x0F;
pub const USB_REQUEST_GET_HANDSHAKE                    : u8 = 0x10;
pub const USB_REQUEST_SET_CONNECTION                   : u8 = 0x11;
pub const USB_REQUEST_SET_SECURITY_DATA                : u8 = 0x12;
pub const USB_REQUEST_GET_SECURITY_DATA                : u8 = 0x13;
pub const USB_REQUEST_SET_WUSB_DATA                    : u8 = 0x14;
pub const USB_REQUEST_LOOPBACK_DATA_WRITE              : u8 = 0x15;
pub const USB_REQUEST_LOOPBACK_DATA_READ               : u8 = 0x16;
pub const USB_REQUEST_SET_INTERFACE_DS                 : u8 = 0x17;

// Standard Feature selectors
pub const USB_FEATURE_ENDPOINT_HALT                    : u8 = 0x0;
pub const USB_FEATURE_SELF_POWERED                     : u8 = 0x0;
pub const USB_FEATURE_REMOTE_WAKEUP                    : u8 = 0x1;
pub const USB_FEATURE_TEST_MODE                        : u8 = 0x2;
pub const USB_FEATURE_BATTERY                          : u8 = 0x2;
pub const USB_FEATURE_BHNPENABLE                       : u8 = 0x3;
pub const USB_FEATURE_WUSBDEVICE                       : u8 = 0x3;
pub const USB_FEATURE_AHNPSUPPORT                      : u8 = 0x4;
pub const USB_FEATURE_AALTHNPSUPPORT                   : u8 = 0x5;
pub const USB_FEATURE_DEBUGMODE                        : u8 = 0x6;

// Language IDs
pub const USB_LANGID_NONE                              : LangId = 0x0000;
pub const USB_LANGID_EN                                : LangId = 0x0009;
pub const USB_LANGID_EN_US                             : LangId = 0x0409; // United States of America
pub const USB_LANGID_EN_GB                             : LangId = 0x0809; // United Kingdom
pub const USB_LANGID_EN_AU                             : LangId = 0x0c09; // Australia
pub const USB_LANGID_EN_CA                             : LangId = 0x1009; // Canada
pub const USB_LANGID_EN_NZ                             : LangId = 0x1409; // New Zealand
pub const USB_LANGID_EN_IE                             : LangId = 0x1809; // Ireland
pub const USB_LANGID_EN_ZA                             : LangId = 0x1c09; // South Africa
pub const USB_LANGID_EN_JM                             : LangId = 0x2009; // Jamaica
pub const USB_LANGID_EN_BZ                             : LangId = 0x2809; // Belize
pub const USB_LANGID_EN_TT                             : LangId = 0x2c09; // Trinidad and Tobago
pub const USB_LANGID_EN_ZW                             : LangId = 0x3009; // Zimbabwe
pub const USB_LANGID_EN_PH                             : LangId = 0x3409; // Philippines
pub const USB_LANGID_EN_HK                             : LangId = 0x3c09; // Hong Kong
pub const USB_LANGID_EN_IN                             : LangId = 0x4009; // India
pub const USB_LANGID_EN_MY                             : LangId = 0x4409; // Malaysia
pub const USB_LANGID_EN_SG                             : LangId = 0x4809; // Singapore
pub const USB_LANGID_EN_AE                             : LangId = 0x4c09; // United Arab Emirates

// Hub protocols
pub const USB_HUB_PROTOCOL_FULL_SPEED                  : u8 = 0x00;
pub const USB_HUB_PROTOCOL_HIGH_SPEED_SINGLE_TT        : u8 = 0x01;
pub const USB_HUB_PROTOCOL_HIGH_SPEED_MULTIPLE_TT      : u8 = 0x02;


/// See USB 2.0 specification, revision 2.0, section 11.24.2
pub const HUB_REQUEST_GET_STATUS                       : u8 = USB_REQUEST_GET_STATUS;
pub const HUB_REQUEST_CLEAR_FEATURE                    : u8 = USB_REQUEST_CLEAR_FEATURE;
pub const HUB_REQUEST_SET_FEATURE                      : u8 = USB_REQUEST_SET_FEATURE;
pub const HUB_REQUEST_GET_DESCRIPTOR                   : u8 = USB_REQUEST_GET_DESCRIPTOR;
pub const HUB_REQUEST_SET_DESCRIPTOR                   : u8 = USB_REQUEST_SET_DESCRIPTOR;
pub const HUB_REQUEST_CLEAR_TT_BUFFER                  : u8 = 0x08;
pub const HUB_REQUEST_RESET_TT                         : u8 = 0x09;
pub const HUB_REQUEST_GET_TT_STATE                     : u8 = 0x0a;
pub const HUB_REQUEST_STOP_TT                          : u8 = 0x0b;
pub const HUB_REQUEST_SET_HUB_DEPTH                    : u8 = 0x0C;

// HID classes - we don't need these at the moment

// HID subclasses
pub const HID_SUBCLASS_BOOT                            : u8 = 0x01;

// HID protocols
pub const HID_PROTOCOL_NONE                            : u8 = 0x00;
pub const HID_PROTOCOL_KEYBOARD                        : u8 = 0x01;
pub const HID_PROTOCOL_MOUSE                           : u8 = 0x02;

// HID Standard requests
pub const HID_REQUEST_GET_REPORT                       : u8 = 0x01;
pub const HID_REQUEST_GET_IDLE                         : u8 = 0x02;
pub const HID_REQUEST_GET_PROTOCOL                     : u8 = 0x03;
pub const HID_REQUEST_SET_REPORT                       : u8 = 0x09;
pub const HID_REQUEST_SET_IDLE                         : u8 = 0x0a;
pub const HID_REQUEST_SET_PROTOCOL                     : u8 = 0x0b;

// HID Reports
pub const HID_REPORT_TYPE_INPUT                        : u8 = 0x01;
pub const HID_REPORT_TYPE_OUTPUT                       : u8 = 0x02;
pub const HID_REPORT_TYPE_FEATURE                      : u8 = 0x03;

// HID Country
pub const HID_REPORT_COUNTRY_NOT_SUPPORTED             : u8 = 0;
pub const HID_REPORT_COUNTRY_ARABIC                    : u8 = 1;
pub const HID_REPORT_COUNTRY_BELGIAN                   : u8 = 2;
pub const HID_REPORT_COUNTRY_CANADIAN_BILINGUAL        : u8 = 3;
pub const HID_REPORT_COUNTRY_CANADIAN_FRENCH           : u8 = 4;
pub const HID_REPORT_COUNTRY_CZECH_REPUBLIC            : u8 = 5;
pub const HID_REPORT_COUNTRY_DANISH                    : u8 = 6;
pub const HID_REPORT_COUNTRY_FINNISH                   : u8 = 7;
pub const HID_REPORT_COUNTRY_FRENCH                    : u8 = 8;
pub const HID_REPORT_COUNTRY_GERMAN                    : u8 = 9;
pub const HID_REPORT_COUNTRY_GREEK                     : u8 = 10;
pub const HID_REPORT_COUNTRY_HEBREW                    : u8 = 11;
pub const HID_REPORT_COUNTRY_HUNGARY                   : u8 = 12;
pub const HID_REPORT_COUNTRY_INTERNATIONAL             : u8 = 13;
pub const HID_REPORT_COUNTRY_ITALIAN                   : u8 = 14;
pub const HID_REPORT_COUNTRY_JAPAN                     : u8 = 15;
pub const HID_REPORT_COUNTRY_KOREAN                    : u8 = 16;
pub const HID_REPORT_COUNTRY_LATIN_AMERICAN            : u8 = 17;
pub const HID_REPORT_COUNTRY_DUTCH                     : u8 = 18;
pub const HID_REPORT_COUNTRY_NORWEGIAN                 : u8 = 19;
pub const HID_REPORT_COUNTRY_PERSIAN                   : u8 = 20;
pub const HID_REPORT_COUNTRY_POLAND                    : u8 = 21;
pub const HID_REPORT_COUNTRY_PORTUGUESE                : u8 = 22;
pub const HID_REPORT_COUNTRY_RUSSIAN                   : u8 = 23;
pub const HID_REPORT_COUNTRY_SLOVAKIAN                 : u8 = 24;
pub const HID_REPORT_COUNTRY_SPANISH                   : u8 = 25;
pub const HID_REPORT_COUNTRY_SWEDISH                   : u8 = 26;
pub const HID_REPORT_COUNTRY_SWISS_FRENCH              : u8 = 27;
pub const HID_REPORT_COUNTRY_SWISS_GERMAN              : u8 = 28;
pub const HID_REPORT_COUNTRY_SWITZERLAND               : u8 = 29;
pub const HID_REPORT_COUNTRY_TAIWAN                    : u8 = 30;
pub const HID_REPORT_COUNTRY_TURKISH_Q                 : u8 = 31;
pub const HID_REPORT_COUNTRY_ENGLISH_UK                : u8 = 32;
pub const HID_REPORT_COUNTRY_ENGLISH_US                : u8 = 33;
pub const HID_REPORT_COUNTRY_YUGOSLAVIAN               : u8 = 34;
pub const HID_REPORT_COUNTRY_TURKISH_F                 : u8 = 35;

// Interface requests
pub const USB_REQUEST_INTERFACE_GET_STATUS             : u8 = 0x00;
pub const USB_REQUEST_INTERFACE_CLEAR_FEATURE          : u8 = 0x01;
pub const USB_REQUEST_INTERFACE_SET_FEATURE            : u8 = 0x03;
pub const USB_REQUEST_INTERFACE_GET_INTERFACE          : u8 = 0x0a;
pub const USB_REQUEST_INTERFACE_SET_INTERFACE          : u8 = 0x11;

// Interface Classes
pub const USB_INTERFACE_CLASS_RESERVED                 : u8 = 0x0;
pub const USB_INTERFACE_CLASS_AUDIO                    : u8 = 0x1;
pub const USB_INTERFACE_CLASS_COMMUNICATIONS           : u8 = 0x2;
pub const USB_INTERFACE_CLASS_HID                      : u8 = 0x3;
pub const USB_INTERFACE_CLASS_PHYSICAL                 : u8 = 0x5;
pub const USB_INTERFACE_CLASS_IMAGE                    : u8 = 0x6;
pub const USB_INTERFACE_CLASS_PRINTER                  : u8 = 0x7;
pub const USB_INTERFACE_CLASS_MASS_STORAGE             : u8 = 0x8;
pub const USB_INTERFACE_CLASS_HUB                      : u8 = 0x9;
pub const USB_INTERFACE_CLASS_CDC_DATA                 : u8 = 0xa;
pub const USB_INTERFACE_CLASS_SMART_CARD               : u8 = 0xb;
pub const USB_INTERFACE_CLASS_CONTENT_SECURITY         : u8 = 0xd;
pub const USB_INTERFACE_CLASS_VIDEO                    : u8 = 0xe;
pub const USB_INTERFACE_CLASS_PERSONAL_HEALTH_CARE     : u8 = 0xf;
pub const USB_INTERFACE_CLASS_AUDIO_VIDEO              : u8 = 0x10;
pub const USB_INTERFACE_CLASS_DIAGNOSTIC_DEVICE        : u8 = 0xdc;
pub const USB_INTERFACE_CLASS_WIRELESS_CONTROLLER      : u8 = 0xe0;
pub const USB_INTERFACE_CLASS_MISCELLANEOUS            : u8 = 0xef;
pub const USB_INTERFACE_CLASS_APPLICATION_SPECIFIC     : u8 = 0xfe;
pub const USB_INTERFACE_CLASS_VENDOR_SPECIFIC          : u8 = 0xff;

// Isochronous synchronization types
pub const USB_ISOCHRONOUS_SYNCHRONIZATION_NONE         : u2 = 0b00;
pub const USB_ISOCHRONOUS_SYNCHRONIZATION_ASYNCHRONOUS : u2 = 0b01;
pub const USB_ISOCHRONOUS_SYNCHRONIZATION_ADAPTIVE     : u2 = 0b10;
pub const USB_ISOCHRONOUS_SYNCHRONIZATION_SYNCHRONOUS  : u2 = 0b11;

// Isochronous usage types
pub const USB_ISOCHRONOUS_USAGE_DATA                   : u2 = 0b00;
pub const USB_ISOCHRONOUS_USAGE_FEEDBACK               : u2 = 0b01;
pub const USB_ISOCHRONOUS_USAGE_EXPLICIT_FEEDBACK      : u2 = 0b10;
pub const USB_ISOCHRONOUS_USAGE_RESERVED               : u2 = 0b11;


// zig fmt: on
