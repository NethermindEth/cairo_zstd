use alexandria_math::BitShift;

use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};

#[derive(Drop)]
struct SequencesHeader {
    num_sequences: u32,
    modes: Option<CompressionModes>,
}

#[derive(Drop, Clone, Copy)]
struct Sequence {
    literals_length: u32,
    match_length: u32,
    offset: u32,
}

#[derive(Drop, Copy)]
struct CompressionModes {
    modes: u8,
}

#[derive(Drop)]
enum ModeType {
    Predefined,
    RLE,
    FSECompressed,
    Repeat,
}

#[generate_trait]
impl CompressionModesImpl of CompressionModesTrait {
    fn decode_mode(m: u8) -> ModeType {
        assert(m >= 0 && m <= 3, 'Invalid compression mode type');

        if m == 0 {
            ModeType::Predefined
        } else if m == 1 {
            ModeType::RLE
        } else if m == 2 {
            ModeType::FSECompressed
        } else {
            ModeType::Repeat
        }
    }

    fn ll_mode(self: @CompressionModes) -> ModeType {
        CompressionModesTrait::decode_mode(BitShift::shr(*self.modes, 6))
    }

    fn of_mode(self: @CompressionModes) -> ModeType {
        CompressionModesTrait::decode_mode(BitShift::shr(*self.modes, 4) & 0x3)
    }

    fn ml_mode(self: @CompressionModes) -> ModeType {
        CompressionModesTrait::decode_mode(BitShift::shr(*self.modes, 2) & 0x3)
    }
}

impl SequencesHeaderDefault of Default<SequencesHeader> {
    fn default() -> SequencesHeader {
        SequencesHeaderTrait::new()
    }
}

#[derive(Drop)]
enum SequencesHeaderParseError {
    NotEnoughBytes: (u8, usize),
}

#[generate_trait]
impl SequencesHeaderImpl of SequencesHeaderTrait {
    fn new() -> SequencesHeader {
        SequencesHeader { num_sequences: 0, modes: Option::None, }
    }

    fn parse_from_header(
        ref self: SequencesHeader, source: @ByteArraySlice
    ) -> Result<u8, SequencesHeaderParseError> {
        let mut bytes_read = 0;
        if source.len() == 0 {
            return Result::Err(SequencesHeaderParseError::NotEnoughBytes((1, 0)));
        }

        if source[0] == 0 {
            self.num_sequences = 0;
            return Result::Ok(1);
        } else if source[0] >= 1 && source[0] <= 127 {
            if source.len() < 2 {
                return Result::Err(SequencesHeaderParseError::NotEnoughBytes((2, source.len())));
            }
            self.num_sequences = source[0].into();
            bytes_read += 1;
        } else if source[0] >= 128 && source[0] <= 254 {
            if source.len() < 3 {
                return Result::Err(SequencesHeaderParseError::NotEnoughBytes((3, source.len())));
            }
            self.num_sequences = BitShift::shl(source[0].into() - 128_u32, 8) + source[1].into();
            bytes_read += 2;
        } else if source[0] == 255 {
            if source.len() < 4 {
                return Result::Err(SequencesHeaderParseError::NotEnoughBytes((4, source.len())));
            }
            self.num_sequences = source[1].into()
                + BitShift::shl(source[2].into(), 8_u32)
                + 0x7F00_u32;
            bytes_read += 3;
        }

        self.modes = Option::Some(CompressionModes { modes: source[bytes_read.into()] });
        bytes_read += 1;

        Result::Ok(bytes_read)
    }
}
