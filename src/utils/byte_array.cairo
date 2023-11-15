use cmp::min;
use bytes_31::BYTES_IN_BYTES31;
use byte_array::ByteArray;

use alexandria_data_structures::byte_array_ext::ByteArrayTraitExt;
use alexandria_data_structures::byte_array_reader::ByteArrayReader;

#[derive(Copy, Drop)]
struct ByteArraySlice {
    data: @ByteArray,
    from: usize,
    len: usize,
}

#[generate_trait]
impl ByteArraySliceImpl of ByteArraySliceTrait {
    fn new(data: @ByteArray, from: usize, end: usize) -> ByteArraySlice {
        let len = end - from;

        assert(data.len() >= from, 'Slice start outside array');
        assert(data.len() - from >= len, 'Slice larger than array');

        ByteArraySlice { data, from, len }
    }

    fn slice(self: @ByteArraySlice, from: usize, end: usize) -> ByteArraySlice {
        ByteArraySliceTrait::new(*self.data, *self.from + from, *self.from + end)
    }

    fn len(self: @ByteArraySlice) -> usize {
        *self.len
    }

    fn at(self: @ByteArraySlice, index: usize) -> Option<u8> {
        if index >= *self.len {
            return Option::None;
        }

        (*self.data).at(index + *self.from)
    }
}

impl ByteArraySliceIndexView of IndexView<ByteArraySlice, usize, u8> {
    fn index(self: @ByteArraySlice, index: usize) -> u8 {
        self.at(index).expect('Index out of bounds')
    }
}

trait ByteArrayTraitExtRead<T> {
    fn word_u16(self: @T, offset: usize) -> Option<u16>;
    fn word_u16_le(self: @T, offset: usize) -> Option<u16>;
    fn word_u32(self: @T, offset: usize) -> Option<u32>;
    fn word_u32_le(self: @T, offset: usize) -> Option<u32>;
    fn word_u64(self: @T, offset: usize) -> Option<u64>;
    fn word_u64_le(self: @T, offset: usize) -> Option<u64>;
    fn word_u128(self: @T, offset: usize) -> Option<u128>;
    fn word_u128_le(self: @T, offset: usize) -> Option<u128>;
    fn reader(self: @T) -> ByteArraySliceReader;
}

impl ByteArraySliceByteArrayTraitExtReadImpl of ByteArrayTraitExtRead<ByteArraySlice> {
    fn word_u16(self: @ByteArraySlice, offset: usize) -> Option<u16> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u16(offset + *self.from)
    }

    fn word_u16_le(self: @ByteArraySlice, offset: usize) -> Option<u16> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u16_le(offset + *self.from)
    }

    fn word_u32(self: @ByteArraySlice, offset: usize) -> Option<u32> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u32(offset + *self.from)
    }

    fn word_u32_le(self: @ByteArraySlice, offset: usize) -> Option<u32> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u32_le(offset + *self.from)
    }

    fn word_u64(self: @ByteArraySlice, offset: usize) -> Option<u64> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u64(offset + *self.from)
    }

    fn word_u64_le(self: @ByteArraySlice, offset: usize) -> Option<u64> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u64_le(offset + *self.from)
    }

    fn word_u128(self: @ByteArraySlice, offset: usize) -> Option<u128> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u128(offset + *self.from)
    }

    fn word_u128_le(self: @ByteArraySlice, offset: usize) -> Option<u128> {
        if offset >= *self.len {
            return Option::None;
        }

        (*self.data).word_u128_le(offset + *self.from)
    }

    fn reader(self: @ByteArraySlice) -> ByteArraySliceReader {
        ByteArraySliceReaderTrait::new(self)
    }
}

impl ByteArraySliceDefault of Default<ByteArraySlice> {
    fn default() -> ByteArraySlice {
        ByteArraySliceTrait::new(Default::default(), 0, 0)
    }
}

#[derive(Copy, Drop)]
struct ByteArraySliceReader {
    data: @ByteArraySlice,
    reader_index: usize,
}

#[generate_trait]
impl ByteArraySliceReaderImpl of ByteArraySliceReaderTrait {
    fn new(from: @ByteArraySlice) -> ByteArraySliceReader {
        ByteArraySliceReader { data: from, reader_index: 0, }
    }

    fn read_u8(ref self: ByteArraySliceReader) -> Option<u8> {
        let byte = self.data.at(self.reader_index)?;
        self.reader_index += 1;
        Option::Some(byte)
    }

    fn read_u16(ref self: ByteArraySliceReader) -> Option<u16> {
        let result = self.data.word_u16(self.reader_index)?;
        self.reader_index += 2;
        Option::Some(result)
    }

    fn read_u16_le(ref self: ByteArraySliceReader) -> Option<u16> {
        let result = self.data.word_u16_le(self.reader_index)?;
        self.reader_index += 2;
        Option::Some(result)
    }

    fn read_u32(ref self: ByteArraySliceReader) -> Option<u32> {
        let result = self.data.word_u32(self.reader_index)?;
        self.reader_index += 4;
        Option::Some(result)
    }

    fn read_u32_le(ref self: ByteArraySliceReader) -> Option<u32> {
        let result = self.data.word_u32_le(self.reader_index)?;
        self.reader_index += 4;
        Option::Some(result)
    }

    fn read_u64(ref self: ByteArraySliceReader) -> Option<u64> {
        let result = self.data.word_u64(self.reader_index)?;
        self.reader_index += 8;
        Option::Some(result)
    }

    fn read_u64_le(ref self: ByteArraySliceReader) -> Option<u64> {
        let result = self.data.word_u64_le(self.reader_index)?;
        self.reader_index += 8;
        Option::Some(result)
    }

    fn read_u128(ref self: ByteArraySliceReader) -> Option<u128> {
        let result = self.data.word_u128(self.reader_index)?;
        self.reader_index += 16;
        Option::Some(result)
    }

    fn read_u128_le(ref self: ByteArraySliceReader) -> Option<u128> {
        let result = self.data.word_u128_le(self.reader_index)?;
        self.reader_index += 16;
        Option::Some(result)
    }

    fn read_u256(ref self: ByteArraySliceReader) -> Option<u256> {
        let result = u256 {
            high: self.data.word_u128(self.reader_index)?,
            low: self.data.word_u128(self.reader_index + 16)?
        };
        self.reader_index += 32;
        Option::Some(result)
    }

    fn read_u256_le(ref self: ByteArraySliceReader) -> Option<u256> {
        let result = u256 {
            low: self.data.word_u128_le(self.reader_index)?,
            high: self.data.word_u128_le(self.reader_index + 16)?
        };
        self.reader_index += 32;
        Option::Some(result)
    }

    fn len(self: @ByteArraySliceReader) -> usize {
        let byte_array = *self.data;
        let byte_array_len = byte_array.len();
        byte_array_len - *self.reader_index
    }
}

#[generate_trait]
impl ByteArrayExtendSliceImpl of ByteArraySliceExtendTrait {
    fn extend_slice(ref self: ByteArray, input: @ByteArraySlice) {
        // also keeping this simple for now
        let mut i: usize = 0;
        loop {
            if i >= input.len() {
                break;
            }

            self.append_byte(input[i]);

            i += 1;
        };
    }
}

#[generate_trait]
impl ByteArrayPushResizeImpl of ByteArrayPushResizeTrait {
    fn push_resize(ref self: ByteArray, new_len: usize, input: u8) {
        assert(new_len >= self.len(), 'invalid push_resize len');

        let mut i: usize = 0;
        let len = new_len - self.len();
        loop {
            if i >= len {
                break;
            }

            self.append_byte(input);

            i += 1;
        }
    }
}
