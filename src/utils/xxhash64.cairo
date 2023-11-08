use alexandria_math::{BitShift};
use alexandria_data_structures::byte_array_ext::{ByteArrayTraitExt};
use alexandria_data_structures::byte_array_reader::{ByteArrayReaderTrait};

use cairo_zstd::utils::math::{Bits, Wrapping};
use cairo_zstd::utils::byte_array::{ByteArraySliceTrait, ByteArrayTraitExtRead};

// Based on the Rust and Zig implementations at, respectively:
// * https://github.com/DoumanAsh/xxhash-rust
// * https://github.com/clownpriest/xxhash

const CHUNK_SIZE: usize = consteval_int!(8 * 4);
const PRIME_1: u64 = 0x9E3779B185EBCA87;
const PRIME_2: u64 = 0xC2B2AE3D27D4EB4F;
const PRIME_3: u64 = 0x165667B19E3779F9;
const PRIME_4: u64 = 0x85EBCA77C2B2AE63;
const PRIME_5: u64 = 0x27D4EB2F165667C5;

#[derive(Drop)]
struct XxHash64 {
    seed: u64,
    v1: u64,
    v2: u64,
    v3: u64,
    v4: u64,
    mem: ByteArray,
    total_len: usize,
}

#[generate_trait]
impl XxHash64Impl of XxHash64Trait {
    fn new(seed: u64) -> XxHash64 {
        XxHash64 {
            seed: seed,
            total_len: 0,
            v1: Wrapping::add(Wrapping::add(seed, PRIME_1), PRIME_2),
            v2: Wrapping::add(seed, PRIME_2),
            v3: seed,
            v4: Wrapping::sub(seed, PRIME_1),
            mem: Default::default(),
        }
    }

    fn update(ref self: XxHash64, input: @ByteArray) {
        self.total_len = self.total_len + input.len();

        if (self.mem.len() + input.len()) < CHUNK_SIZE {
            self.mem.append(input);
            return;
        }

        let mut p: usize = 0;

        if self.mem.len() > 0 {
            let fill_len = CHUNK_SIZE - self.mem.len();

            append_word(ref self.mem, input, 0, fill_len);

            let mem = @self.mem;

            self.v1 = round(self.v1, mem.word_u64_le(0).unwrap());
            self.v2 = round(self.v2, mem.word_u64_le(8).unwrap());
            self.v3 = round(self.v3, mem.word_u64_le(16).unwrap());
            self.v4 = round(self.v4, mem.word_u64_le(24).unwrap());

            p += fill_len;
            self.mem = Default::default();
        }

        if input.len() - p >= CHUNK_SIZE {
            loop {
                self.v1 = round(self.v1, input.word_u64_le(p).unwrap());
                p += 8;
                self.v2 = round(self.v2, input.word_u64_le(p).unwrap());
                p += 8;
                self.v3 = round(self.v3, input.word_u64_le(p).unwrap());
                p += 8;
                self.v4 = round(self.v4, input.word_u64_le(p).unwrap());
                p += 8;

                if input.len() - p < CHUNK_SIZE {
                    break;
                }
            };
        }

        if input.len() - p > 0 {
            append_word(ref self.mem, input, p, input.len() - p);
        }
    }

    fn digest(self: @XxHash64) -> u64 {
        let mut result: u64 = 0;

        if *self.total_len >= CHUNK_SIZE {
            result =
                Wrapping::add(
                    Wrapping::add(Wrapping::add(rol1(*self.v1), rol7(*self.v2)), rol12(*self.v3)),
                    rol18(*self.v4)
                );

            result = merge_round(result, *self.v1);
            result = merge_round(result, *self.v2);
            result = merge_round(result, *self.v3);
            result = merge_round(result, *self.v4);
        } else {
            result = Wrapping::add(*self.v3, PRIME_5);
        }

        result = Wrapping::add(result, (*self.total_len).into());

        finalize(result, self.mem)
    }
}

#[inline]
fn round(acc: u64, input: u64) -> u64 {
    Wrapping::mul(rol31(Wrapping::add(acc, Wrapping::mul(input, PRIME_2))), PRIME_1)
}

#[inline]
fn merge_round(mut acc: u64, val: u64) -> u64 {
    acc = acc ^ round(0, val);
    Wrapping::add(Wrapping::mul(acc, PRIME_1), PRIME_4)
}

#[inline]
fn avalanche(mut input: u64) -> u64 {
    input = input ^ BitShift::shr(input, 33);
    input = Wrapping::mul(input, PRIME_2);
    input = input ^ BitShift::shr(input, 29);
    input = Wrapping::mul(input, PRIME_3);
    input = input ^ BitShift::shr(input, 32);
    input
}

fn finalize(mut input: u64, data: @ByteArray) -> u64 {
    let mut reader = data.reader();

    loop {
        if !(reader.len() >= 8) {
            break;
        }

        input = input ^ round(0, reader.read_u64_le().unwrap());
        input = Wrapping::add(Wrapping::mul(rol27(input), PRIME_1), PRIME_4);
    };

    if reader.len() >= 4 {
        input = input ^ Wrapping::mul(reader.read_u32_le().unwrap().into(), PRIME_1);
        input = Wrapping::add(Wrapping::mul(rol23(input), PRIME_2), PRIME_3);
    }

    loop {
        if reader.len() == 0 {
            break;
        }

        input = input ^ Wrapping::mul(reader.read_u8().unwrap().into(), PRIME_5);
        input = Wrapping::mul(rol11(input), PRIME_1);
    };

    avalanche(input)
}

fn rol1(u: u64) -> u64 {
    return BitShift::shl(u, 1) | BitShift::shr(u, 63);
}

fn rol7(u: u64) -> u64 {
    return BitShift::shl(u, 7) | BitShift::shr(u, 57);
}

fn rol11(u: u64) -> u64 {
    return BitShift::shl(u, 11) | BitShift::shr(u, 53);
}

fn rol12(u: u64) -> u64 {
    return BitShift::shl(u, 12) | BitShift::shr(u, 52);
}

fn rol18(u: u64) -> u64 {
    return BitShift::shl(u, 18) | BitShift::shr(u, 46);
}

fn rol23(u: u64) -> u64 {
    return BitShift::shl(u, 23) | BitShift::shr(u, 41);
}

fn rol27(u: u64) -> u64 {
    return BitShift::shl(u, 27) | BitShift::shr(u, 37);
}

fn rol31(u: u64) -> u64 {
    return BitShift::shl(u, 31) | BitShift::shr(u, 33);
}

fn append_word(ref ba: ByteArray, input: @ByteArray, offset: usize, len: usize) {
    // keeping it simple for now
    let mut i: usize = offset;
    loop {
        if i >= offset + len {
            break;
        }

        ba.append_byte(input[i]);

        i += 1;
    }
}
