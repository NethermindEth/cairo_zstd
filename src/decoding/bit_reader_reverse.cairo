use cmp::min;
use integer::BoundedInt;
use bytes_31::{one_shift_left_bytes_u128};
use debug::PrintTrait;

use alexandria_data_structures::byte_array_ext::{ByteArrayTraitExt};
use alexandria_math::{BitShift, pow};

use cairo_zstd::decoding::bit_reader::{GetBitsError};
use cairo_zstd::utils::math::{
    I32TryIntoU32, I32TryIntoU64, U32TryIntoI32, I64TryIntoU64, U64TryIntoI64, I64TryIntoI32,
    I32TryIntoU8, U8TryIntoI32, I32Div,
};
use cairo_zstd::utils::types::isize;
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait, ByteArrayTraitExtRead};

#[derive(Drop)]
struct BitReaderReversed {
    idx: isize,
    source: @ByteArraySlice,
    bit_container: u64,
    bits_in_container: u64,
}

fn word_u48_le(self: @ByteArraySlice, offset: usize) -> Option<u64> {
    let b1 = self.at(offset)?;
    let b2 = self.at(offset + 1)?;
    let b3 = self.at(offset + 2)?;
    let b4 = self.at(offset + 3)?;
    let b5 = self.at(offset + 4)?;
    let b6 = self.at(offset + 5)?;

    Option::Some(
        b1.into()
            + b2.into() * one_shift_left_bytes_u128(1).try_into().unwrap()
            + b3.into() * one_shift_left_bytes_u128(2).try_into().unwrap()
            + b4.into() * one_shift_left_bytes_u128(3).try_into().unwrap()
            + b5.into() * one_shift_left_bytes_u128(4).try_into().unwrap()
            + b6.into() * one_shift_left_bytes_u128(5).try_into().unwrap()
    )
}

#[generate_trait]
impl BitReaderReversedImpl of BitReaderReversedTrait {
    fn bits_remaining(self: @BitReaderReversed) -> isize {
        let bits_in_container_i64: i64 = (*self.bits_in_container).try_into().unwrap();
        let bits_in_container_i32: i32 = bits_in_container_i64.try_into().unwrap();

        (*self.idx) + bits_in_container_i32.into()
    }

    fn new(source: @ByteArraySlice) -> BitReaderReversed {
        BitReaderReversed {
            idx: source.len().try_into().unwrap() * 8,
            source,
            bit_container: 0,
            bits_in_container: 0
        }
    }

    fn refill_container(ref self: BitReaderReversed) {
        let byte_idx: usize = self.byte_idx().try_into().unwrap();

        let retain_bytes = (self.bits_in_container + 7) / 8;
        let want_to_read_bits = 64 - (retain_bytes * 8);

        if byte_idx >= 8 {
            self
                .refill_fast(
                    byte_idx,
                    retain_bytes.try_into().unwrap(),
                    want_to_read_bits.try_into().unwrap()
                )
        } else {
            self.refill_slow(byte_idx, want_to_read_bits.try_into().unwrap())
        }
    }

    fn refill_fast(
        ref self: BitReaderReversed, byte_idx: usize, retain_bytes: u8, want_to_read_bits: u8
    ) {
        let load_from_byte_idx: usize = byte_idx - 7 + retain_bytes.into();
        let refill = self.source.word_u64_le(load_from_byte_idx).unwrap();
        self.bit_container = refill;
        self.bits_in_container += want_to_read_bits.into();
        self.idx -= want_to_read_bits.into();
    }

    fn refill_slow(ref self: BitReaderReversed, byte_idx: usize, want_to_read_bits: u8) {
        let can_read_bits: u8 = min(want_to_read_bits, self.idx.try_into().unwrap());
        let can_read_bytes = can_read_bits / 8;

        if can_read_bytes == 8 {
            self.bit_container = self.source.word_u64_le(byte_idx - 7).unwrap();
            self.bits_in_container += 64;
            self.idx -= 64;
        } else if can_read_bytes == 6 || can_read_bytes == 7 {
            self.bit_container = BitShift::shl(self.bit_container, 48);
            self.bits_in_container += 48;
            self.bit_container = self.bit_container
                | (word_u48_le(self.source, byte_idx - 5).unwrap());
            self.idx -= 48;
        } else if can_read_bytes == 4 || can_read_bytes == 5 {
            self.bit_container = BitShift::shl(self.bit_container, 32);
            self.bits_in_container += 32;
            self.bit_container = self.bit_container
                | self.source.word_u32_le(byte_idx - 3).unwrap().into();
            self.idx -= 32;
        } else if can_read_bytes == 2 || can_read_bytes == 3 {
            self.bit_container = BitShift::shl(self.bit_container, 16);
            self.bits_in_container += 16;
            self.bit_container = self.bit_container
                | self.source.word_u16_le(byte_idx - 1).unwrap().into();
            self.idx -= 16;
        } else if can_read_bytes == 1 {
            self.bit_container = BitShift::shl(self.bit_container, 8);
            self.bits_in_container += 8;
            self.bit_container = self.bit_container | self.source.at(byte_idx).unwrap().into();
            self.idx -= 8;
        } else {
            panic_with_felt252('This cannot be reached');
        }
    }

    fn byte_idx(self: @BitReaderReversed) -> isize {
        (*self.idx - 1) / 8
    }

    fn get_bits(ref self: BitReaderReversed, n: u8) -> Result<u64, GetBitsError> {
        if n == 0 {
            return Result::Ok(0);
        }
        if self.bits_in_container >= n.into() {
            return Result::Ok(self.get_bits_unchecked(n));
        }

        self.get_bits_cold(n)
    }

    fn get_bits_cold(ref self: BitReaderReversed, n: u8) -> Result<u64, GetBitsError> {
        if n > 56 {
            return Result::Err(GetBitsError::TooManyBits((n.into(), 56)));
        }

        let signed_n: isize = n.into();

        if self.bits_remaining() <= 0 {
            self.idx -= signed_n;
            return Result::Ok(0);
        }

        if self.bits_remaining() < signed_n {
            let emulated_read_shift = signed_n - self.bits_remaining();
            let v = self.get_bits(self.bits_remaining().try_into().unwrap()).unwrap();
            assert(self.idx == 0, 'Idx should not be 0');
            let value = BitShift::shl(v, emulated_read_shift.try_into().unwrap());
            self.idx -= emulated_read_shift;
            return Result::Ok(value);
        }

        loop {
            if !(self.bits_in_container < n.into() && self.idx > 0) {
                break;
            }

            self.refill_container();
        };

        assert(self.bits_in_container >= n.into(), 'Bits in container < n');

        Result::Ok(self.get_bits_unchecked(n))
    }

    #[inline]
    fn get_bits_triple(
        ref self: BitReaderReversed, n1: u8, n2: u8, n3: u8,
    ) -> Result<(u64, u64, u64), GetBitsError> {
        let sum: usize = n1.into() + n2.into() + n3.into();
        if sum == 0 {
            return Result::Ok((0, 0, 0));
        }
        if sum > 56 {
            // try and get the values separatly
            return Result::Ok((self.get_bits(n1)?, self.get_bits(n2)?, self.get_bits(n3)?));
        }

        if self.bits_in_container >= sum.into() {
            let v1 = if n1 == 0 {
                0
            } else {
                self.get_bits_unchecked(n1)
            };
            let v2 = if n2 == 0 {
                0
            } else {
                self.get_bits_unchecked(n2)
            };
            let v3 = if n3 == 0 {
                0
            } else {
                self.get_bits_unchecked(n3)
            };

            return Result::Ok((v1, v2, v3));
        }

        self.get_bits_triple_cold(n1, n2, n3, sum.try_into().unwrap())
    }

    fn get_bits_triple_cold(
        ref self: BitReaderReversed, n1: u8, n2: u8, n3: u8, sum: u8,
    ) -> Result<(u64, u64, u64), GetBitsError> {
        let sum_signed: isize = sum.into();

        if self.bits_remaining() <= 0 {
            self.idx -= sum_signed;
            return Result::Ok((0, 0, 0));
        }

        if self.bits_remaining() < sum_signed {
            return Result::Ok((self.get_bits(n1)?, self.get_bits(n2)?, self.get_bits(n3)?));
        }

        loop {
            if !(self.bits_in_container < sum.into() && self.idx > 0) {
                break;
            }

            self.refill_container();
        };

        assert(self.bits_in_container >= sum.into(), 'Not enough bits in container');

        //if we reach this point there are enough bits in the container

        let v1 = if n1 == 0 {
            0
        } else {
            self.get_bits_unchecked(n1)
        };
        let v2 = if n2 == 0 {
            0
        } else {
            self.get_bits_unchecked(n2)
        };
        let v3 = if n3 == 0 {
            0
        } else {
            self.get_bits_unchecked(n3)
        };

        Result::Ok((v1, v2, v3))
    }

    #[inline]
    fn get_bits_unchecked(ref self: BitReaderReversed, n: u8) -> u64 {
        let shift_by = self.bits_in_container - n.into();
        let mask = BitShift::shl(1_u64, n.into()) - 1;

        let value = BitShift::shr(self.bit_container, shift_by);
        self.bits_in_container -= n.into();
        let value_masked = value & mask;

        assert(value_masked < BitShift::shl(1, n.into()), 'Masking failed');

        value_masked
    }

    fn reset(ref self: BitReaderReversed, new_source: @ByteArraySlice) {
        self.idx = new_source.len().try_into().unwrap() * 8;
        self.source = new_source;
        self.bit_container = 0;
        self.bits_in_container = 0;
    }
}
