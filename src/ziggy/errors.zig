pub const ForthError = error{
    TooManyEntries,
    NotFound,
    OverFlow,
    UnderFlow,
    BadOperation,
    WordReadError,
    ParseError,
    OutOfMemory,
    EOF,
};
