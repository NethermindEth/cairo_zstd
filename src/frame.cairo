use alexandria_math::BitShift;
use alexandria_data_structures::byte_array_ext::{ByteArrayTraitExt, ByteArrayReaderTrait};

const MAGIC_NUM: u32 = 0xFD2F_B528;
const MIN_WINDOW_SIZE: u64 = 1024;
const MAX_WINDOW_SIZE: u64 = 4123168604160; // (1 << 41) + 7 * (1 << 38)

#[derive(Drop)]
struct Frame {
    header: FrameHeader,
}

#[derive(Drop)]
struct FrameHeader {
    descriptor: FrameDescriptor,
    window_descriptor: u8,
    dict_id: Option<u32>,
    frame_content_size: u64,
}

#[derive(Drop)]
struct FrameDescriptor {
    descriptor: u8,
}

#[derive(Drop)]
enum FrameDescriptorError {
    InvalidFrameContentSizeFlag: (u8,),
}

#[generate_trait]
impl FrameDescriptorImpl of FrameDescriptorTrait {
    fn frame_content_size_flag(self: @FrameDescriptor) -> u8 {
        BitShift::shr(*self.descriptor, 6)
    }

    fn reserved_flag(self: @FrameDescriptor) -> bool {
        (BitShift::shr(*self.descriptor, 3) & 0x1) == 1
    }

    fn single_segment_flag(self: @FrameDescriptor) -> bool {
        (BitShift::shr(*self.descriptor, 5) & 0x1) == 1
    }

    fn content_checksum_flag(self: @FrameDescriptor) -> bool {
        (BitShift::shr(*self.descriptor, 2) & 0x1) == 1
    }

    fn dict_id_flag(self: @FrameDescriptor) -> u8 {
        *self.descriptor & 0x3
    }

    fn frame_content_size_bytes(self: @FrameDescriptor) -> Result<u8, FrameDescriptorError> {
        let flag = self.frame_content_size_flag();

        if flag == 0 {
            if self.single_segment_flag() {
                Result::Ok(1)
            } else {
                Result::Ok(0)
            }
        } else if flag == 1 {
            Result::Ok(2)
        } else if flag == 2 {
            Result::Ok(4)
        } else if flag == 3 {
            Result::Ok(8)
        } else {
            Result::Err(FrameDescriptorError::InvalidFrameContentSizeFlag((flag,)))
        }
    }

    fn dictionary_id_bytes(self: @FrameDescriptor) -> Result<u8, FrameDescriptorError> {
        let flag = self.dict_id_flag();

        if flag == 0 {
            Result::Ok(0)
        } else if flag == 1 {
            Result::Ok(1)
        } else if flag == 2 {
            Result::Ok(2)
        } else if flag == 3 {
            Result::Ok(4)
        } else {
            Result::Err(FrameDescriptorError::InvalidFrameContentSizeFlag((flag,)))
        }
    }
}

#[derive(Drop)]
enum FrameHeaderError {
    WindowTooBig: (u64,),
    WindowTooSmall: (u64,),
    FrameDescriptorError: FrameDescriptorError,
    DictIdTooSmall: (usize, usize),
    MismatchedFrameSize: (usize, u8),
    FrameSizeIsZero,
    InvalidFrameSize: (u8,),
}

#[generate_trait]
impl FrameHeaderImpl of FrameHeaderTrait {
    fn window_size(self: @FrameHeader) -> Result<u64, FrameHeaderError> {
        if self.descriptor.single_segment_flag() {
            Result::Ok(self.frame_content_size())
        } else {
            let exp: u64 = BitShift::shr(*self.window_descriptor, 3).into();
            let mantissa: u64 = (*self.window_descriptor & 0x7).into();

            let window_log = 10 + exp;
            let window_base = BitShift::shl(1, window_log);
            let window_add = (window_base / 8) * mantissa;

            let window_size = window_base + window_add;

            if window_size >= MIN_WINDOW_SIZE {
                if window_size < MAX_WINDOW_SIZE {
                    Result::Ok(window_size)
                } else {
                    Result::Err(FrameHeaderError::WindowTooBig((window_size,)))
                }
            } else {
                Result::Err(FrameHeaderError::WindowTooSmall((window_size,)))
            }
        }
    }

    fn dictionary_id(self: @FrameHeader) -> Option<u32> {
        *self.dict_id
    }

    fn frame_content_size(self: @FrameHeader) -> u64 {
        *self.frame_content_size
    }
}

#[derive(Drop)]
enum ReadFrameHeaderError {
    MagicNumberReadError,
    FrameDescriptorReadError,
    DictionaryIdReadError,
    WindowDescriptorReadError,
    FrameContentSizeReadError,
    InvalidFrameDescriptor: FrameDescriptorError,
    BadMagicNumber: (u32,),
    SkipFrame: (u32, u32),
}

fn read_frame_header(ba: @ByteArray) -> Result<(Frame, u8), ReadFrameHeaderError> {
    let mut reader = ba.reader();

    let magic_num = match reader.read_u32_le() {
        Option::Some(val) => val,
        Option::None => { return Result::Err(ReadFrameHeaderError::MagicNumberReadError); },
    };

    if magic_num >= 0x184D2A50 && magic_num <= 0x184D2A5F {
        let skip_size = match reader.read_u32_le() {
            Option::Some(val) => val,
            Option::None => { return Result::Err(ReadFrameHeaderError::FrameDescriptorReadError); },
        };
        return Result::Err(ReadFrameHeaderError::SkipFrame((magic_num, skip_size)));
    }

    if magic_num != MAGIC_NUM {
        return Result::Err(ReadFrameHeaderError::BadMagicNumber(((magic_num,))));
    }

    let descriptor = match reader.read_u8() {
        Option::Some(val) => val,
        Option::None => { return Result::Err(ReadFrameHeaderError::FrameDescriptorReadError); },
    };

    let desc = FrameDescriptor { descriptor: descriptor };

    let mut frame_header = FrameHeader {
        descriptor: FrameDescriptor { descriptor: descriptor },
        dict_id: Option::None,
        frame_content_size: 0,
        window_descriptor: 0,
    };

    if !desc.single_segment_flag() {
        frame_header.window_descriptor = match reader.read_u8() {
            Option::Some(val) => val,
            Option::None => {
                return Result::Err(ReadFrameHeaderError::WindowDescriptorReadError);
            },
        };
    }

    let dict_id_len: usize = match desc.dictionary_id_bytes() {
        Result::Ok(val) => { val.into() },
        Result::Err(err) => {
            return Result::Err(ReadFrameHeaderError::InvalidFrameDescriptor(err));
        },
    };

    if dict_id_len != 0 {
        let mut dict_id = if dict_id_len == 1 {
            match reader.read_u8() {
                Option::Some(val) => val.into(),
                Option::None => {
                    return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
                },
            }
        } else if dict_id_len == 2 {
            match reader.read_u16_le() {
                Option::Some(val) => val.into(),
                Option::None => {
                    return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
                },
            }
        } else if dict_id_len == 4 {
            match reader.read_u32_le() {
                Option::Some(val) => val,
                Option::None => {
                    return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
                },
            }
        } else {
            return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
        };

        if dict_id != 0 {
            frame_header.dict_id = Option::Some(dict_id);
        }
    }

    let fcs_len: usize = match desc.frame_content_size_bytes() {
        Result::Ok(val) => { val.into() },
        Result::Err(err) => {
            return Result::Err(ReadFrameHeaderError::InvalidFrameDescriptor(err));
        },
    };

    if fcs_len != 0 {
        let mut fcs = if fcs_len == 1 {
            match reader.read_u8() {
                Option::Some(val) => val.into(),
                Option::None => {
                    return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
                },
            }
        } else if fcs_len == 2 {
            match reader.read_u16_le() {
                Option::Some(val) => val.into(),
                Option::None => {
                    return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
                },
            }
        } else if fcs_len == 4 {
            match reader.read_u32_le() {
                Option::Some(val) => val.into(),
                Option::None => {
                    return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
                },
            }
        } else if fcs_len == 8 {
            match reader.read_u64_le() {
                Option::Some(val) => val,
                Option::None => {
                    return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
                },
            }
        } else {
            return Result::Err(ReadFrameHeaderError::DictionaryIdReadError);
        };

        if fcs_len == 2 {
            fcs += 256;
        }

        frame_header.frame_content_size = fcs;
    }

    let frame: Frame = Frame { header: frame_header, };

    Result::Ok((frame, reader.reader_index.try_into().unwrap()))
}
