// Following a trail of dead links, the USB 2.0 spec points to the USB
// document library, which no longer publishes the list. Instead it
// refers to the MSDN library, which says to use locale names instead
// of langID codes. Great, except the hardware devices only send the
// codes. Eventually, the "MS-LCID: Windows Language Code Identifier
// (LCID) Reference" has a link to a PDF with actual numbers.
//
// See therefore
// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-lcid/70feba9f-294e-491e-b6eb-56532684c37f
// and the linked PDF (dated 6/25/2021)
// https://winprotocoldoc.blob.core.windows.net/productionwindowsarchives/MS-LCID/%5bMS-LCID%5d.pdf
//
// We won't be using all these codes, but after all that work there
// was no way I was only going to include en_US.

pub const LangID = struct {
    pub const none: u16 = 0x0000;
    pub const en: u16 = 0x0009;
    pub const en_US: u16 = 0x0409; // United States of America
    pub const en_GB: u16 = 0x0809; // United Kingdom
    pub const en_AU: u16 = 0x0c09; // Australia
    pub const en_CA: u16 = 0x1009; // Canada
    pub const en_NZ: u16 = 0x1409; // New Zealand
    pub const en_IE: u16 = 0x1809; // Ireland
    pub const en_ZA: u16 = 0x1c09; // South Africa
    pub const en_JM: u16 = 0x2009; // Jamaica
    pub const en_BZ: u16 = 0x2809; // Belize
    pub const en_TT: u16 = 0x2c09; // Trinidad and Tobago
    pub const en_ZW: u16 = 0x3009; // Zimbabwe
    pub const en_PH: u16 = 0x3409; // Philippines
    pub const en_HK: u16 = 0x3c09; // Hong Kong
    pub const en_IN: u16 = 0x4009; // India
    pub const en_MY: u16 = 0x4409; // Malaysia
    pub const en_SG: u16 = 0x4809; // Singapore
    pub const en_AE: u16 = 0x4c09; // United Arab Emirates
};
