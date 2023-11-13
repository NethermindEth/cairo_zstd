use cairo_zstd::decoding::bit_reader::GetBitsError;
use alexandria_math::BitShift;

struct LiteralsSection {
    regenerated_size: u32,
    compressed_size: Option<u32>,
    num_streams: Option<u8>,
    ls_type: LiteralsSectionType,
}

enum LiteralsSectionType {
    Raw, 
    RLE,
    Compressed,
    Treeless,
}

#[non_exhaustive]
enum LiteralsSectionParseError {
    IllegalLiteralSectionType (u8, ),
    GetBitsError(GetBitsError,),
    NotEnoughBytes (usize,u8 ),
}

// impl LiteralsSectionTypeDisplayImpl of Display<>

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

    fn header_bytes_needed(ref self:LiteralsSection:, first_byte: u8) -> Result<u8, LiteralsSectionParseError> {
        let ls_type: u8 = Self::section_type(first_byte.try_into().unwrap());
        let size_format = BitShift::shr(first_byte, 2) & 0x3;
        match ls_type {
            LiteralsSectionType::RLE || LiteralsSectionType::Raw => {
                if size_format == 0 || size_format == 2 {
                    Result::Ok(1)
                }
                else if size_format == 1 {
                    Result::Ok(2)
                }
                else if size_format == 3 {
                    Result::Ok(3)
                }
                else {
                    panic_with_felt252(
                        "This is a bug in the program. There should only be values between 0..3"
                    ),
                }
            }
            LiteralsSectionType::Compressed || LiteralsSectionType::Treeless => {
                if size_format == 0 || size_format == 1 {
                    Result::Ok(3)
                }
                else if size_format == 2 {
                    Result::Ok(4)
                }
                else if size_format == 3 {
                    Result::Ok(5)
                }
                else {
                    panic_with_felt252(
                        "This is a bug in the program. There should only be values between 0..3"
                    ),
                }
            }
        }
    }

    fn parse_from_header(ref self:LiteralsSection , raw: ByteArraySlice) -> Result<u8, LiteralsSectionParseError> {
        let mut br = BitReaderTrait::new(@raw);
        let num_bits: u8 = 2;
        let t = match br.get_bits(num_bits) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(LiteralsSectionParseError::GetBitsError(err)); }
        };
        let self.ls_type = Self::section_type(t) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType(err)); }
        };
        let size_format = match br.get_bits(num_bits) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(LiteralsSectionParseError::GetBitsError(err)); }
        };

        let byte_needed = match self.header_bytes_needed(raw[0]) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(LiteralsSectionParseError::NotEnoughBytes(err)); }
        }
        if raw.len() < byte_needed: usize {
            return  Result::Err(LiteralsSectionParseError::NotEnoughBytes(
                have: raw.len(),
                need: byte_needed,
            )); 
        }

        match self.ls_type {
            LiteralsSectionType::RLE || LiteralsSectionType::Raw => {
                self.compressed_size = Option::None;

                if size_format == 0 || size_format == 2{
                    self.regenerated_size: u32 = BitShift::shr(raw[0], 3).try_into().unwrap;
                    Result::Ok(1)
                }
                else if size_format == 1 {
                    self.regenerated_size: u32 = 
                        (BitShift::shr(raw[0], 4).try_into().unwrap) + 
                        (BitShift::shr(raw[1], 4).try_into().unwrap);
                    Result::Ok(2)
                } 
                else if size_format == 3 {
                    self.regenerated_size: u32 = 
                        (BitShift::shr(raw[0], 4).try_into().unwrap) + 
                        (BitShift::shr(raw[1], 4).try_into().unwrap) + 
                        (BitShift::shr(raw[2], 4).try_into().unwrap);
                    Result::Ok(3)
                }
                else {
                    panic_with_felt252(
                        "This is a bug in the program. There should only be values between 0..3"
                    ),
                }
            }
            LiteralsSectionType::Compressed || LieralsSectionType::Treeless => {
                if size_format == 0 { 
                    self.num_streams = Option::Some(1);
                }
                else if size_format == 1 || size_format == 2 || size_format ==3 {
                    self.num_streams = Option::Some(4);
                }
                else {
                    panic_with_felt252 (
                        "This is a bug in the program. There should only be values between 0..3"
                    )
                }

                if size_format == 0 || if size_format == 1{
                    self.regenerated_size =
                        (BitShift::shr(raw[0], 4).try_into().unwrap) + 
                        (BitShift::shl(raw[1] && 0x3f, 4).try_into().unwrap);

                    self.compressed_size = Option::Some(
                        (BitShift::shr(raw[1], 6).try_into().unwrap) + 
                        (BitShift::shl(raw[2], 2).try_into().unwrap),
                        );
                    Result::Ok(3)
                } 
                if else size_format == 2 {
                    self.regenerated_size =
                        (BitShift::shr(raw[0], 4).try_into().unwrap) + 
                        (BitShift::shl(raw[1], 4).try_into().unwrap) + 
                        (BitShift::shl(raw[1] && 0x3, 12).try_into().unwrap);

                    self.compressed_size = Option::Some(
                            (BitShift::shr(raw[2], 2).try_into().unwrap) + 
                            (BitShift::shl(raw[3], 6).try_into().unwrap),
                        );
                    Result::Ok(4)
                }
                if else size_format == 3 {
                    self.regenerated_size =
                        (BitShift::shr(raw[0], 4).try_into().unwrap) + 
                        (BitShift::shl(raw[1], 4).try_into().unwrap) + 
                        (BitShift::shl(raw[1] && 0x3F, 12).try_into().unwrap);

                    self.compressed_size = Option::Some(
                            (BitShift::shr(raw[3], 2).try_into().unwrap) + 
                            (BitShift::shl(raw[4], 10).try_into().unwrap),
                        );
                    Result::Ok(5)
                } 
                else{
                    panic_with_felt252(
                        "This is a bug in the program. There should only be values between 0..3"
                    ),
                }
            }
        }
    }

    fn section_type(raw: u8) -> Result<LiteralsSectionType, LiteralsSectionParseError> {
        let t = raw && 0x3;
        match t {
            0 => Result::Ok(LiteralsSectionType::Raw),
            1 => Result::Ok(LiteralsSectionType::RLE),
            2 => Result::Ok(LiteralsSectionType::Compressed),
            3 => Result::Ok(LiteralsSectionType::Treeless),
            _ => Result::Err(LiteralsSectionParseError::IllegalLiteralSectionType(u8))
        }
    }
}