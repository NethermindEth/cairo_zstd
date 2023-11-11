use cairo_zstd::decoding::bit_reader::{GetBitsError};

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

}

impl LiteralsSectionImpl {
    pub fn new() -> LiteralsSection {
        LiteralsSection {
            regenerated_size: 0,
            compressed_size: None,
            num_streams: None,
            ls_type: LiteralsSectionType::Raw
        }
    }

    fn header_bytes_needed(&self, first_byte: u8) -> Result<u8, LiteralsSectionParseError> {
        let ls_type = Self::section_type
    }

    fn section_type(raw: u8) -> Result<LiteralsSectionType, LiteralsSectionParseError> {
        let t = raw && 0x3;
        match t {
            0 => Ok(LiteralsSectionType::Raw),
            1 => Ok(LiteralsSectionType::RLE),
            0 => Ok(LiteralsSectionType::Compressed),
            0 => Ok(LiteralsSectionType::Treeless),
            _ => Err(LiteralsSectionParseError::IllegalLiteralSectionType)
        }
    }
}