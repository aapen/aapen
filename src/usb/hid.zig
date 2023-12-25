/// Protocol definition for USB 2.0 Human Interface Devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
const descriptor = @import("descriptor.zig");
const BCD = descriptor.BCD;
const DescriptorType = descriptor.DescriptorType;
const Header = descriptor.Header;

pub const StandardHidRequests = enum(u8) {
    get_report = 1,
    get_idle = 2,
    get_protocol = 3,
    set_report = 9,
    set_idle = 10,
    set_protocol = 11,
};

pub const HidReportType = enum(u8) {
    input = 1,
    output = 2,
    feature = 3,
};

pub const HidCountry = enum(u8) {
    CountryNotSupported = 0,
    Arabic = 1,
    Belgian = 2,
    CanadianBilingual = 3,
    CanadianFrench = 4,
    CzechRepublic = 5,
    Danish = 6,
    Finnish = 7,
    French = 8,
    German = 9,
    Greek = 10,
    Hebrew = 11,
    Hungary = 12,
    International = 13,
    Italian = 14,
    Japan = 15,
    Korean = 16,
    LatinAmerican = 17,
    Dutch = 18,
    Norwegian = 19,
    Persian = 20,
    Poland = 21,
    Portuguese = 22,
    Russian = 23,
    Slovakian = 24,
    Spanish = 25,
    Swedish = 26,
    SwissFrench = 27,
    SwissGerman = 28,
    Switzerland = 29,
    Taiwan = 30,
    TurkishQ = 31,
    EnglishUk = 32,
    EnglishUs = 33,
    Yugoslavian = 34,
    TurkishF = 35,
};

pub const HidDescriptor = extern struct {
    header: Header,
    hid_version: BCD,
    country_code: HidCountry,
    descriptor_count: u8,
    descriptor_type: DescriptorType,
    length: u16,
};
