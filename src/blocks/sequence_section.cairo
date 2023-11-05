use fmt::Display;

struct SequencesHeader {
    num_sequences: u32,
    modes: Option<CompressionModes>,
}

#[derive(Clone, Copy)]
struct Sequence {
    ll: u32,
    ml: u32,
    ol: u32,
}

impl SequenceImpl of Display<Sequence> {
    fn fmt(self: @Sequence, ref f: Formatter) -> Result<(), Error> {
        f.buffer.append("LL: {}", ll);
        f.buffer.append(" ML: {}", ml);
        f.buffer.append(" OF: {}", ol);
    }
}

#[derive(Copy, Clone)];
enum ModeType {
    Predefined,
    RLE,
    FSECompressed,
    Repeat,
}

impl CompressionModes {
    fn decode_mode(m: u8) -> ModeType {
        match m {
            0 => ModeType::Predefined,
            1 => ModeType::RLE,
            2 => ModeType::FSECompressed,
            3 => ModeType::Repeat,
            _ => panic("This can never happen"),
        }
    }

    fn ll_mode(self: @CompressionModes) -> ModeType {
        self.decode_mode((self.0 >> 6) & 0x3)
    }

    fn ou_mode(self: @CompressionModes) -> ModeType {
        self.decode_mode((self.0 >> 4) & 0x3)
    }

    fn ml_mode(self: @CompressionModes) -> ModeType {
        self.decode_mode((self.0 >> 2) & 0x3)
    }
}

impl SequencesHeaderImpl of Default {
    fn default() -> Self {
        Self::new()
    }
}

enum SequencesHeaderParseError {
    need_at_least: u8,
    got: usize,
}

impl SequencesHeaderParseErrorImpl of Display{
    fn fmt(&self, f: &mut Formatter) -> Result<(), Error> {
        f.buffer.append(f, "source must have at least {} bytes to parse header; got {} bytes", self.need_at_least, self.got)
    }

    fn parse_from_header(&mut self, source: &[u8]) -> Result<u8, SequencesHeaderParseError> {
    let mut bytes_read = 0;

    if source.is_empty() {
        return Err(SequencesHeaderParseError::NotEnoughBytes {
            need_at_least: 1,
            got: 0,
        });
    }
}

}
