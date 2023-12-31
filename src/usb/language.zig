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

pub const LangID = enum(u16) {
    none = 0x0000,
    en = 0x0009,
    en_US = 0x0409, // United States of America
    en_GB = 0x0809, // United Kingdom
    en_AU = 0x0c09, // Australia
    en_CA = 0x1009, // Canada
    en_NZ = 0x1409, // New Zealand
    en_IE = 0x1809, // Ireland
    en_ZA = 0x1c09, // South Africa
    en_JM = 0x2009, // Jamaica
    en_BZ = 0x2809, // Belize
    en_TT = 0x2c09, // Trinidad and Tobago
    en_ZW = 0x3009, // Zimbabwe
    en_PH = 0x3409, // Philippines
    en_HK = 0x3c09, // Hong Kong
    en_IN = 0x4009, // India
    en_MY = 0x4409, // Malaysia
    en_SG = 0x4809, // Singapore
    en_AE = 0x4c09, // United Arab Emirates

};
