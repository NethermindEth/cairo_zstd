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

        assert(data.len() - from <= len, 'Slice larger than array');

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
    fn reader(self: @T) -> ByteArrayReader;
}

impl ByteArraySliceByteArrayTraitExtReadImpl of ByteArrayTraitExtRead<ByteArraySlice> {
    fn word_u16(self: @ByteArraySlice, offset: usize) -> Option<u16> {
        (*self.data).word_u16(offset)
    }
    fn word_u16_le(self: @ByteArraySlice, offset: usize) -> Option<u16> {
        (*self.data).word_u16_le(offset)
    }
    fn word_u32(self: @ByteArraySlice, offset: usize) -> Option<u32> {
        (*self.data).word_u32(offset)
    }
    fn word_u32_le(self: @ByteArraySlice, offset: usize) -> Option<u32> {
        (*self.data).word_u32_le(offset)
    }
    fn word_u64(self: @ByteArraySlice, offset: usize) -> Option<u64> {
        (*self.data).word_u64(offset)
    }
    fn word_u64_le(self: @ByteArraySlice, offset: usize) -> Option<u64> {
        (*self.data).word_u64_le(offset)
    }
    fn word_u128(self: @ByteArraySlice, offset: usize) -> Option<u128> {
        (*self.data).word_u128(offset)
    }
    fn word_u128_le(self: @ByteArraySlice, offset: usize) -> Option<u128> {
        (*self.data).word_u128_le(offset)
    }
    fn reader(self: @ByteArraySlice) -> ByteArrayReader {
        (*self.data).reader()
    }
}
