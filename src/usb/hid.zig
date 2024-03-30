/// Protocol definition for USB 2.0 Human Interface Devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
const descriptor = @import("descriptor.zig");
const BCD = descriptor.BCD;
const Header = descriptor.Header;

pub const StandardHidRequests = struct {
    pub const get_report: u8 = 1;
    pub const get_idle: u8 = 2;
    pub const get_protocol: u8 = 3;
    pub const set_report: u8 = 9;
    pub const set_idle: u8 = 10;
    pub const set_protocol: u8 = 11;
};

pub const HidReportType = struct {
    pub const input: u8 = 1;
    pub const output: u8 = 2;
    pub const feature: u8 = 3;
};

pub const HidCountry = struct {
    pub const CountryNotSupported: u8 = 0;
    pub const Arabic: u8 = 1;
    pub const Belgian: u8 = 2;
    pub const CanadianBilingual: u8 = 3;
    pub const CanadianFrench: u8 = 4;
    pub const CzechRepublic: u8 = 5;
    pub const Danish: u8 = 6;
    pub const Finnish: u8 = 7;
    pub const French: u8 = 8;
    pub const German: u8 = 9;
    pub const Greek: u8 = 10;
    pub const Hebrew: u8 = 11;
    pub const Hungary: u8 = 12;
    pub const International: u8 = 13;
    pub const Italian: u8 = 14;
    pub const Japan: u8 = 15;
    pub const Korean: u8 = 16;
    pub const LatinAmerican: u8 = 17;
    pub const Dutch: u8 = 18;
    pub const Norwegian: u8 = 19;
    pub const Persian: u8 = 20;
    pub const Poland: u8 = 21;
    pub const Portuguese: u8 = 22;
    pub const Russian: u8 = 23;
    pub const Slovakian: u8 = 24;
    pub const Spanish: u8 = 25;
    pub const Swedish: u8 = 26;
    pub const SwissFrench: u8 = 27;
    pub const SwissGerman: u8 = 28;
    pub const Switzerland: u8 = 29;
    pub const Taiwan: u8 = 30;
    pub const TurkishQ: u8 = 31;
    pub const EnglishUk: u8 = 32;
    pub const EnglishUs: u8 = 33;
    pub const Yugoslavian: u8 = 34;
    pub const TurkishF: u8 = 35;
};

pub const HidDescriptor = extern struct {
    header: Header,
    hid_version: BCD,
    country_code: u8,
    descriptor_count: u8,
    descriptor_type: u8,
    length: u16,
};
