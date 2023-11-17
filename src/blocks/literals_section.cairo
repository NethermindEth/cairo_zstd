use byte_array::ByteArray;

use alexandria_math::BitShift;

use cairo_zstd::decoding::bit_reader::{BitReader, BitReaderTrait, GetBitsError};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};

#[derive(Drop)]
struct LiteralsSection {
    regenerated_size: u32,
    compressed_size: Option<u32>,
    num_streams: Option<u8>,
    ls_type: LiteralsSectionType,
}

#[derive(Drop, PartialEq)]
enum LiteralsSectionType {
    Raw,
    RLE,
    Compressed,
    Treeless,
}

#[derive(Drop)]
enum LiteralsSectionParseError {
    IllegalLiteralSectionType: (u8,),
    IllegalSizeFormat: (u8,),
    GetBitsError: GetBitsError,
    NotEnoughBytes: (usize, u8),
}

impl LiteralsSectionDefault of Default<LiteralsSection> {
    fn default() -> LiteralsSection {
        LiteralsSectionTrait::new()
    }
}

#[generate_trait]
impl LiteralsSectionImpl of LiteralsSectionTrait {
    fn new() -> LiteralsSection {
        LiteralsSection {
            regenerated_size: 0,
            compressed_size: Option::None,
            num_streams: Option::None,
            ls_type: LiteralsSectionType::Raw,
        }
    }

    fn header_bytes_needed(
        self: @LiteralsSection, first_byte: u8
    ) -> Result<u8, LiteralsSectionParseError> {
        let ls_type = LiteralsSectionTrait::section_type(first_byte)?;
        let size_format = BitShift::shr(first_byte, 2) & 0x3;

        if ls_type == LiteralsSectionType::RLE || ls_type == LiteralsSectionType::Raw {
            if size_format == 0 || size_format == 2 {
                Result::Ok(1)
            } else if size_format == 1 {
                Result::Ok(2)
            } else if size_format == 3 {
                Result::Ok(3)
            } else {
                Result::Err(LiteralsSectionParseError::IllegalSizeFormat((size_format,)))
            }
        } else if ls_type == LiteralsSectionType::Compressed
            || ls_type == LiteralsSectionType::Treeless {
            if size_format == 0 || size_format == 1 {
                Result::Ok(3)
            } else if size_format == 2 {
                Result::Ok(4)
            } else if size_format == 3 {
                Result::Ok(5)
            } else {
                Result::Err(LiteralsSectionParseError::IllegalSizeFormat((size_format,)))
            }
        } else {
            Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType((first_byte,)))
        }
    }

    fn parse_from_header(
        ref self: LiteralsSection, raw: @ByteArraySlice
    ) -> Result<u8, LiteralsSectionParseError> {
        let mut br = BitReaderTrait::new(raw);
        let t: u8 = match br.get_bits(2) {
            Result::Ok(val) => val.try_into().unwrap(),
            Result::Err(err) => {
                return Result::Err(LiteralsSectionParseError::GetBitsError(err));
            },
        };
        self.ls_type = LiteralsSectionTrait::section_type(t)?;
        let size_format = match br.get_bits(2) {
            Result::Ok(val) => val.try_into().unwrap(),
            Result::Err(err) => {
                return Result::Err(LiteralsSectionParseError::GetBitsError(err));
            },
        };

        let byte_needed = self.header_bytes_needed(raw[0])?;
        if raw.len() < byte_needed.into() {
            return Result::Err(LiteralsSectionParseError::NotEnoughBytes((raw.len(), byte_needed)));
        }

        if self.ls_type == LiteralsSectionType::RLE || self.ls_type == LiteralsSectionType::Raw {
            self.compressed_size = Option::None;

            if size_format == 0 || size_format == 2 {
                self.regenerated_size = BitShift::shr(raw[0].into(), 3_u32);
                Result::Ok(1)
            } else if size_format == 1 {
                self.regenerated_size = BitShift::shr(raw[0].into(), 4_u32)
                    + BitShift::shl(raw[1].into(), 4_u32);
                Result::Ok(2)
            } else if size_format == 3 {
                self.regenerated_size = BitShift::shr(raw[0].into(), 4_u32)
                    + BitShift::shl(raw[1].into(), 4_u32)
                    + BitShift::shl(raw[2].into(), 12_u32);
                Result::Ok(3)
            } else {
                Result::Err(LiteralsSectionParseError::IllegalSizeFormat((size_format,)))
            }
        } else if self.ls_type == LiteralsSectionType::Compressed
            || self.ls_type == LiteralsSectionType::Treeless {
            if size_format == 0 {
                self.num_streams = Option::Some(1);
            } else if size_format >= 1 && size_format <= 3 {
                self.num_streams = Option::Some(4);
            } else {
                return Result::Err(LiteralsSectionParseError::IllegalSizeFormat((size_format,)));
            }

            if size_format == 0 || size_format == 1 {
                self.regenerated_size = BitShift::shr(raw[0].into(), 4_u32)
                    + BitShift::shl(raw[1].into() & 0x3f_u32, 4);

                self
                    .compressed_size =
                        Option::Some(
                            BitShift::shr(raw[1].into(), 6_u32)
                                + BitShift::shl(raw[2].into(), 2_u32)
                        );

                Result::Ok(3)
            } else if size_format == 2 {
                self.regenerated_size = BitShift::shr(raw[0].into(), 4_u32)
                    + BitShift::shl(raw[1].into(), 4_u32)
                    + BitShift::shl(raw[2].into() & 0x3_u32, 12);

                self
                    .compressed_size =
                        Option::Some(
                            BitShift::shr(raw[2].into(), 2_u32)
                                + BitShift::shl(raw[3].into(), 6_u32)
                        );
                Result::Ok(4)
            } else if size_format == 3 {
                self.regenerated_size = BitShift::shr(raw[0].into(), 4_u32)
                    + BitShift::shl(raw[1].into(), 4_u32)
                    + BitShift::shl(raw[2].into() & 0x3f_u32, 12);

                self
                    .compressed_size =
                        Option::Some(
                            BitShift::shr(raw[2].into(), 6_u32)
                                + BitShift::shl(raw[3].into(), 2)
                                + BitShift::shl(raw[4].into(), 10),
                        );
                Result::Ok(5)
            } else {
                Result::Err(LiteralsSectionParseError::IllegalSizeFormat((size_format,)))
            }
        } else {
            Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType((t,)))
        }
    }

    fn section_type(raw: u8) -> Result<LiteralsSectionType, LiteralsSectionParseError> {
        let t = raw & 0x3;

        if t == 0 {
            Result::Ok(LiteralsSectionType::Raw)
        } else if t == 1 {
            Result::Ok(LiteralsSectionType::RLE)
        } else if t == 2 {
            Result::Ok(LiteralsSectionType::Compressed)
        } else if t == 3 {
            Result::Ok(LiteralsSectionType::Treeless)
        } else {
            Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType((t,)))
        }
    }
}
