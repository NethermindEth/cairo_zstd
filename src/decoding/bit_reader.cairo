use alexandria_math::{BitShift, pow};

use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait, ByteArrayTraitExtRead};

#[derive(Drop)]
struct BitReader {
    idx: usize,
    source: @ByteArraySlice,
}

#[derive(Copy, Drop)]
enum GetBitsError {
    TooManyBits: (usize, u8),
    NotEnoughRemainingBits: (usize, usize),
}

#[generate_trait]
impl BitReaderImpl of BitReaderTrait {
    fn new(source: @ByteArraySlice) -> BitReader {
        BitReader { idx: 0, source }
    }

    fn bits_left(ref self: BitReader) -> usize {
        self.source.len() * 8 - self.idx
    }

    fn bits_read(self: @BitReader) -> usize {
        *self.idx
    }

    fn return_bits(ref self: BitReader, n: usize) {
        if n > self.idx {
            panic_with_felt252('Cant return this many bits');
        }
        self.idx -= n;
    }

    fn get_bits(ref self: BitReader, n: usize) -> Result<u64, GetBitsError> {
        if n > 64 {
            return Result::Err(GetBitsError::TooManyBits((n, 64)));
        }
        if self.bits_left() < n {
            return Result::Err(GetBitsError::NotEnoughRemainingBits((n, self.bits_left())));
        }

        let old_idx = self.idx;

        let bits_left_in_current_byte = 8 - (self.idx % 8);
        let bits_not_needed_in_current_byte = 8 - bits_left_in_current_byte;

        let mut value: u64 = BitShift::shr(
            self.source.at(self.idx / 8).unwrap().into(), bits_not_needed_in_current_byte
        )
            .into();

        if bits_left_in_current_byte.into() >= n {
            value = value & (BitShift::shl(1, n).into() - 1);
            self.idx += n;
        } else {
            self.idx += bits_left_in_current_byte;

            let full_bytes_needed = (n - bits_left_in_current_byte) / 8;
            let bits_in_last_byte_needed = n - bits_left_in_current_byte - full_bytes_needed * 8;

            assert(
                bits_left_in_current_byte + full_bytes_needed * 8 + bits_in_last_byte_needed == n,
                ''
            );

            let mut bit_shift = bits_left_in_current_byte;

            assert(self.idx % 8 == 0, '');

            let mut i: usize = 0;
            loop {
                if i >= full_bytes_needed {
                    break;
                }

                let source_val: u64 = self.source.at(self.idx / 8).unwrap().into();

                value = value | BitShift::shl(source_val, bit_shift.into());
                self.idx += 8;
                bit_shift += 8;

                i += 1;
            };

            assert(n - bit_shift == bits_in_last_byte_needed, '');

            if bits_in_last_byte_needed > 0 {
                let source_val: u64 = self.source.at(self.idx / 8).unwrap().into();

                let val_las_byte = source_val
                    & (BitShift::shl(1, bits_in_last_byte_needed).into() - 1);
                value = value | BitShift::shl(val_las_byte, bit_shift.into()).into();
                self.idx += bits_in_last_byte_needed;
            }
        };

        assert(self.idx == old_idx + n, '');

        Result::Ok(value)
    }

    fn reset(ref self: BitReader, new_source: @ByteArraySlice) {
        self.idx = 0;
        self.source = new_source;
    }
}
