use byte_array::ByteArray;
use cairo_zstd::decoding::bit_reader::{BitReaderTrait, GetBitsError};
use cairo_zstd::decoding::bit_reader_reverse::{BitReaderReversedTrait};
use alexandria_math::{BitShift};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};
use debug::PrintTrait;

#[derive(Drop)]
struct LiteralsSection {
    regenerated_size: u32,
    compressed_size: Option<u32>,
    num_streams: Option<u8>,
    ls_type: LiteralsSectionType,
}

#[derive(Drop)]
enum LiteralsSectionType {
    Raw,
    RLE,
    Compressed,
    Treeless,
}

#[derive(Drop, Copy)]
enum LiteralsSectionParseError {
    IllegalLiteralSectionType: (u8,),
    GetBitsError: GetBitsError,
    NotEnoughBytes: (usize, u8),
    CustomError: (felt252,),
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
            ls_type: LiteralsSectionType::Raw
        }
    }

    fn header_bytes_needed(
        self: @LiteralsSection, first_byte: u8
    ) -> Result<u8, LiteralsSectionParseError> {
        let ls_type = LiteralsSectionTrait::section_type(first_byte);
        match ls_type {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType((2,)));
            },
        };

        let size_format = BitShift::shr(first_byte, 2) & 0x3;

        match self.ls_type {
            LiteralsSectionType::Raw => {
                if size_format == 0 || size_format == 2 {
                    Result::Ok(1)
                } else if size_format == 1 {
                    Result::Ok(2)
                } else if size_format == 3 {
                    Result::Ok(3)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
            LiteralsSectionType::RLE => {
                if size_format == 0 || size_format == 2 {
                    Result::Ok(1)
                } else if size_format == 1 {
                    Result::Ok(2)
                } else if size_format == 3 {
                    Result::Ok(3)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
            LiteralsSectionType::Compressed => {
                if size_format == 0 || size_format == 1 {
                    Result::Ok(3)
                } else if size_format == 2 {
                    Result::Ok(4)
                } else if size_format == 3 {
                    Result::Ok(5)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
            LiteralsSectionType::Treeless => {
                if size_format == 0 || size_format == 1 {
                    Result::Ok(3)
                } else if size_format == 2 {
                    Result::Ok(4)
                } else if size_format == 3 {
                    Result::Ok(5)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
        }
    }

    fn parse_from_header(
        ref self: LiteralsSection, raw: @ByteArraySlice
    ) -> Result<u8, LiteralsSectionParseError> {
        let mut br = BitReaderReversedTrait::new(raw);
        let t: u8 = match br.get_bits(2) {
            Result::Ok(t) => { t.try_into().unwrap() },
            Result::Err(err) => {
                return Result::Err(LiteralsSectionParseError::GetBitsError(err));
            }
        };
        let ls_type = match LiteralsSectionTrait::section_type(t) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType((2,)));
            },
        };

        let size_format: u8 = match br.get_bits(2) {
            Result::Ok(size_format) => { size_format.try_into().unwrap() },
            Result::Err(err) => {
                return Result::Err(LiteralsSectionParseError::GetBitsError(err));
            }
        };

        let byte_needed = match self.header_bytes_needed(raw[0]) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType((2,)));
            },
        };

        let raw_length: u8 = raw.len().try_into().unwrap();
        if raw_length < byte_needed {
            return Result::Err(
                LiteralsSectionParseError::NotEnoughBytes((raw.len(), byte_needed,))
            );
        }

        match ls_type {
            LiteralsSectionType::Raw => {
                self.compressed_size = Option::None;

                if size_format == 0 || size_format == 2 {
                    self.regenerated_size = BitShift::shr(raw[0], 3).into();
                    Result::Ok(1)
                } else if size_format == 1 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shr(raw[1], 4).into());
                    Result::Ok(2)
                } else if size_format == 3 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shr(raw[1], 4).into())
                        + (BitShift::shr(raw[2], 4).into());
                    Result::Ok(3)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
            LiteralsSectionType::RLE => {
                self.compressed_size = Option::None;

                if size_format == 0 || size_format == 2 {
                    self.regenerated_size = BitShift::shr(raw[0], 3).into();
                    Result::Ok(1)
                } else if size_format == 1 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shr(raw[1], 4).into());
                    Result::Ok(2)
                } else if size_format == 3 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shr(raw[1], 4).into())
                        + (BitShift::shr(raw[2], 4).into());
                    Result::Ok(3)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
            LiteralsSectionType::Compressed => {
                if size_format == 0 {
                    self.num_streams = Option::Some(1);
                } else if size_format == 1 || size_format == 2 || size_format == 3 {
                    self.num_streams = Option::Some(4);
                } else {
                    panic_with_felt252('Values should be between 0..3');
                }

                if size_format == 0 || size_format == 1 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shl((raw[1] & 0x3f), 4).into());

                    self
                        .compressed_size =
                            Option::Some(
                                (BitShift::shr(raw[1], 6).into())
                                    + (BitShift::shl(raw[2], 2).into()),
                            );
                    Result::Ok(3)
                } else if size_format == 2 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shl(raw[1], 4).into())
                        + (BitShift::shl((raw[2] & 0x3), 12).into());

                    self
                        .compressed_size =
                            Option::Some(
                                (BitShift::shr(raw[2], 2).into())
                                    + (BitShift::shl(raw[3], 6).into()),
                            );
                    Result::Ok(4)
                } else if size_format == 3 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shl(raw[1], 4).into())
                        + (BitShift::shl((raw[1] & 0x3F), 12).into());

                    self
                        .compressed_size =
                            Option::Some(
                                (BitShift::shr(raw[3], 6).into())
                                    + (BitShift::shl(raw[3], 2).into())
                                    + (BitShift::shl(raw[4], 10).into()),
                            );
                    Result::Ok(5)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
            LiteralsSectionType::Treeless => {
                if size_format == 0 {
                    self.num_streams = Option::Some(1);
                } else if size_format == 1 || size_format == 2 || size_format == 3 {
                    self.num_streams = Option::Some(4);
                } else {
                    panic_with_felt252('Values should be between 0..3');
                }

                if size_format == 0 || size_format == 1 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shl((raw[1] & 0x3f), 4).into());

                    self
                        .compressed_size =
                            Option::Some(
                                (BitShift::shr(raw[1], 6).into())
                                    + (BitShift::shl(raw[2], 2).into()),
                            );
                    Result::Ok(3)
                } else if size_format == 2 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shl(raw[1], 4).into())
                        + (BitShift::shl((raw[2] & 0x3), 12).into());

                    self
                        .compressed_size =
                            Option::Some(
                                (BitShift::shr(raw[2], 2).into())
                                    + (BitShift::shl(raw[3], 6).into()),
                            );
                    Result::Ok(4)
                } else if size_format == 3 {
                    self.regenerated_size = (BitShift::shr(raw[0], 4).into())
                        + (BitShift::shl(raw[1], 4).into())
                        + (BitShift::shl((raw[1] & 0x3F), 12).into());

                    self
                        .compressed_size =
                            Option::Some(
                                (BitShift::shr(raw[3], 6).into())
                                    + (BitShift::shl(raw[3], 2).into())
                                    + (BitShift::shl(raw[4], 10).into()),
                            );
                    Result::Ok(5)
                } else {
                    Result::Err(
                        LiteralsSectionParseError::CustomError(('Only values between 0..3',))
                    )
                }
            },
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
