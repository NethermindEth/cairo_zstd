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
}

#[generate_trait]
impl ByteArrayExtendSliceImpl of ByteArraySliceExtendTrait {
    fn extend_slice(ref self: ByteArray, input: ByteArraySlice) {
        let mut i: usize = 0;
        loop {
            let len = min(input.len() - i * 31, BYTES_IN_BYTES31);

            if len == 0 {
                break;
            }

            if len == BYTES_IN_BYTES31 {
                self.append_word((*input.data.data.at(i)).into(), len);
            } else {
                self.append_word(*input.data.pending_word, len)
            }

            i += 1;
        };
    }
}
