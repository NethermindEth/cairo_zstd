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

enum SequencesHeaderParseError {
    NotEnoughBytes { u8, usize },
}

#[generate_trait]
impl SequencesHeaderImpl of SequencesHeaderTrait {
    fn new() -> SequencesHeader {
        SequencesHeader {
            num_sequences: 0,
            modes: Option::None,
        } 
    }

    fn parse_from_header(ref self:SequencesHeader , source: ByteArraySlice) -> Result<u8, LiteralsSectionParseError> {
        let mut bytes_read = 0;
        if source.is_empty() {
            return Err(SequencesHeaderParseError::NotEnoughBytes(
                need_at_least: 1,
                got: 0
            ));
        }

        let source = match source[0] {
            0 => {
                self.num_sequences = 0;
                return Result::Ok(1);
            }
            if source >= 1 && source <= 127 => {
                if source.len() < 2 {
                    return Err(SequencesHeaderParseError::NotEnoughBytes(
                    need_at_least: 2,
                    got: source.len(),
                    ));
                }
                self.num_sequences:u32 = (raw[0]).try_into().unwrap;
                bytes_read += 1;
                
            }
        }
    }

}