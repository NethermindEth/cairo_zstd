struct SequencesHeader {
    num_sequences: u32,
    modes: Option<ModeType>,
}

#[derive(Clone, Copy)]
struct Sequence {
    ll: u32,
    ml: u32,
    ol: u32,
}

#[derive(Copy, Clone)]
struct CompressionModes<u8> {}

#[derive(Copy, Clone)]
enum ModeType {
    Predefined,
    RLE,
    FSECompressed,
    Repeat,
}


enum SequencesHeaderParseError {
    need_at_least: u8,
    got: usize,
}

