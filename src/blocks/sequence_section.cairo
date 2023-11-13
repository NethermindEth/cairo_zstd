use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};
use alexandria_math::BitShift;

#[derive(Clone, Copy)]
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

#[generate_trait]
impl CompressionModesImpl of CompressionModesTrait {
    fn decode_mode(m: u8) -> ModeType {
        match m {
            0 => ModeType::Predefined,
            1 => ModeType::RLE,
            2 => ModeType::FSECompressed,
            3 => ModeType::Repeat,
            _ => panic_with_felt252("This can never happen"),
        }
    }

    fn ll_mode(self) -> ModeType {
        Self::decode_mode(BitShift::shr((source[0]), 6))
    }

    fn of_mode(self) -> ModeType {
        Self::decode_mode(BitShift::shr((source[0]), 4) && 0x3)
    }

    fn ml_mode(self) -> ModeType {
        Self::decode_mode(BitShift::shr((source[0]), 2) && 0x3)
    }
}

impl SequencesHeaderDefault of Default<SequencesHeader> {
    fn default() -> Self {
        SequencesHeaderTrait::new()
    }
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
            if source == 0 {
                self.num_sequences = 0;
                return Result::Ok(1);
            }
            else if source >= 1 && source <= 127 {
                if source.len() < 2 {
                    return Err(SequencesHeaderParseError::NotEnoughBytes(
                    need_at_least: 2,
                    got: source.len(),
                    ));
                }
                self.num_sequences:u32 = (source[0]).try_into().unwrap;
                bytes_read += 1;
                ByteArraySliceTrait::new(source, 1, source.len());
            }
            else if source >= 128 && source <= 254 {
                if source.len() < 3 {
                    return Err(SequencesHeaderParseError::NotEnoughBytes(
                    need_at_least: 3,
                    got: source.len(),
                    ));
                }
                self.num_sequences: u32 = (BitShift::shl((source[0]) - 128, 8).try_into().unwrap) + (source[1]).try_into().unwrap;
                bytes_read += 2;
                ByteArraySliceTrait::new(source, 2, source.len());
            }
            else if source == {
                if source.len() < 4 {
                    return Err(SequencesHeaderParseError::NotEnoughBytes(
                    need_at_least: 4,
                    got: source.len(),
                    ));
                }
                self.num_sequences: u32 = (source[1]).try_into().unwrap + (BitShift::shl((source[2]), 8).try_into().unwrap) + 0x7F00 ;
                bytes_read += 3;
                ByteArraySliceTrait::new(source, 3, source.len());
            }
        };

        self.modes = Option::Some(CompressionModes(source[0]));
        bytes_read += 1;

        Result::Ok(bytes_read);
    }
}