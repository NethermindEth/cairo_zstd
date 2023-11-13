use byte_array::ByteArray;

use alexandria_math::BitShift;
use alexandria_data_structures::vec::{VecTrait, Felt252Vec, NullableVec};

use cairo_zstd::decoding::bit_reader_reverse::{
    BitReaderReversed, BitReaderReversedTrait, GetBitsError
};
use cairo_zstd::fse::fse_decoder::{
    FSEDecoder, FSEDecoderError, FSEDecoderTrait, FSETable, FSETableError, FSETableTrait
};
use cairo_zstd::utils::math::{HighestBitSet, IsPowerOfTwo};
use cairo_zstd::utils::vec::{Concat, Clear, Resize};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};

#[derive(Destruct)]
struct HuffmanTable {
    decode: NullableVec<Entry>,
    weights: Felt252Vec<u8>,
    max_num_bits: u8,
    bits: Felt252Vec<u8>,
    bit_ranks: Felt252Vec<u32>,
    rank_indexes: Felt252Vec<usize>,
    fse_table: FSETable,
}

#[derive(Drop)]
enum HuffmanTableError {
    SourceIsEmpty,
    NotEnoughBytesForWeights: (usize, u8),
    ExtraPadding: (i32,),
    TooManyWeights: (usize,),
    MissingWeights,
    LeftoverIsNotAPowerOf2: (u32,),
    NotEnoughBytesToDecompressWeights: (usize, usize),
    FSETableUsedTooManyBytes: (usize, u8),
    NotEnoughBytesInSource: (usize, usize),
    WeightBiggerThanMaxNumBits: (u8,),
    MaxBitsTooHigh: (u8,),
    GetBitsError: GetBitsError,
    FSEDecoderError: FSEDecoderError,
    FSETableError: FSETableError,
}

#[derive(Destruct)]
struct HuffmanDecoder {
    table: HuffmanTable,
    state: u64,
}

#[derive(Drop)]
enum HuffmanDecoderError {
    GetBitsError: GetBitsError,
}

#[derive(Copy, Drop)]
struct Entry {
    symbol: u8,
    num_bits: u8,
}

impl EntryFelt252DictValue of Felt252DictValue<Entry> {
    fn zero_default() -> Entry nopanic {
        Entry { symbol: 0, num_bits: 0 }
    }
}

const MAX_MAX_NUM_BITS: u8 = 11;

#[generate_trait]
impl HuffmanDecoderImpl of HuffmanDecoderTrait {
    fn new(table: HuffmanTable) -> HuffmanDecoder {
        HuffmanDecoder { table, state: 0 }
    }

    fn decode_symbol(ref self: HuffmanDecoder) -> u8 {
        let entry: Entry = self.table.decode[self.state.try_into().unwrap()];

        entry.symbol
    }

    fn init_state(
        ref self: HuffmanDecoder, ref br: BitReaderReversed,
    ) -> Result<u8, HuffmanDecoderError> {
        let num_bits = self.table.max_num_bits;
        let new_bits = match br.get_bits(num_bits) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(HuffmanDecoderError::GetBitsError(err)); }
        };
        self.state = new_bits;
        Result::Ok(num_bits)
    }

    fn next_state(
        ref self: HuffmanDecoder, ref br: BitReaderReversed,
    ) -> Result<u8, HuffmanDecoderError> {
        let entry: Entry = self.table.decode[self.state.try_into().unwrap()];
        let num_bits = entry.num_bits;
        let new_bits = match br.get_bits(num_bits) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(HuffmanDecoderError::GetBitsError(err)); }
        };
        self.state = BitShift::shl(self.state, num_bits.into());
        self.state = self.state & (self.table.decode.len().into() - 1);
        self.state = self.state | new_bits;
        Result::Ok(num_bits)
    }
}

impl HuffmanTableDefault of Default<HuffmanTable> {
    fn default() -> HuffmanTable {
        HuffmanTableTrait::new()
    }
}

#[generate_trait]
impl HuffmanTableImpl of HuffmanTableTrait {
    fn new() -> HuffmanTable {
        HuffmanTable {
            decode: VecTrait::new(),
            weights: VecTrait::new(),
            max_num_bits: 0,
            bits: VecTrait::new(),
            bit_ranks: VecTrait::new(),
            rank_indexes: VecTrait::new(),
            fse_table: FSETableTrait::new(),
        }
    }

    fn reinit_from(ref self: HuffmanTable, ref other: HuffmanTable) {
        self.reset();
        self.decode.concat(ref other.decode);
        self.weights.concat(ref other.weights);
        self.max_num_bits = other.max_num_bits;
        self.bits.concat(ref other.bits);
        self.rank_indexes.concat(ref other.rank_indexes);
        self.fse_table.reinit_from(ref other.fse_table);
    }

    fn reset(ref self: HuffmanTable) {
        self.decode.clear();
        self.weights.clear();
        self.max_num_bits = 0;
        self.bits.clear();
        self.bit_ranks.clear();
        self.rank_indexes.clear();
        self.fse_table.reset();
    }

    fn build_decoder(
        ref self: HuffmanTable, source: ByteArraySlice
    ) -> Result<u32, HuffmanTableError> {
        self.decode.clear();

        let bytes_used = self.read_weights(source)?;
        self.build_table_from_weights()?;
        Result::Ok(bytes_used)
    }

    fn read_weights(
        ref self: HuffmanTable, source: ByteArraySlice
    ) -> Result<u32, HuffmanTableError> {
        if source.len() == 0 {
            return Result::Err(HuffmanTableError::SourceIsEmpty);
        }
        let header = source[0];
        let mut bits_read = 8;

        if header >= 0 && header <= 127 {
            let fse_stream = source.slice(1, source.len());

            if header.into() > fse_stream.len() {
                return Result::Err(
                    HuffmanTableError::NotEnoughBytesForWeights((fse_stream.len(), header))
                );
            }
            let bytes_used_by_fse_header = match self.fse_table.build_decoder(fse_stream, 100) {
                Result::Ok(val) => val,
                Result::Err(err) => { return Result::Err(HuffmanTableError::FSETableError(err)); },
            };

            if bytes_used_by_fse_header > header.into() {
                return Result::Err(
                    HuffmanTableError::FSETableUsedTooManyBytes((bytes_used_by_fse_header, header))
                );
            }

            let mut dec1 = FSEDecoderTrait::new(ref self.fse_table);
            let mut dec2 = FSEDecoderTrait::new(ref self.fse_table);

            let compressed_start = bytes_used_by_fse_header;
            let compressed_length = header.into() - bytes_used_by_fse_header;

            let compressed_weights = fse_stream.slice(compressed_start, fse_stream.len());
            if compressed_weights.len() < compressed_length {
                return Result::Err(
                    HuffmanTableError::NotEnoughBytesToDecompressWeights(
                        (compressed_weights.len(), compressed_length)
                    )
                );
            }
            let compressed_weights = compressed_weights.slice(0, compressed_length);
            let mut br = BitReaderReversedTrait::new(@compressed_weights);

            bits_read += (bytes_used_by_fse_header + compressed_length) * 8;

            let mut skipped_bits = 0;
            let result = loop {
                let val = match br.get_bits(1) {
                    Result::Ok(val) => val,
                    Result::Err(err) => {
                        break Result::Err(HuffmanTableError::GetBitsError(err));
                    },
                };

                skipped_bits += 1;
                if val == 1 || skipped_bits > 8 {
                    break Result::Ok(());
                }
            };
            if result.is_err() {
                return Result::Err(result.unwrap_err());
            }
            if skipped_bits > 8 {
                return Result::Err(HuffmanTableError::ExtraPadding((skipped_bits,)));
            }

            match dec1.init_state(ref br) {
                Result::Ok(()) => {},
                Result::Err(err) => {
                    return Result::Err(HuffmanTableError::FSEDecoderError(err));
                },
            };
            match dec2.init_state(ref br) {
                Result::Ok(()) => {},
                Result::Err(err) => {
                    return Result::Err(HuffmanTableError::FSEDecoderError(err));
                },
            };

            self.weights.clear();

            let result = loop {
                let w = dec1.decode_symbol();
                self.weights.push(w);

                match dec1.update_state(ref br) {
                    Result::Ok(()) => {},
                    Result::Err(err) => {
                        break Result::Err(HuffmanTableError::FSEDecoderError(err));
                    },
                };

                if br.bits_remaining() <= -1 {
                    self.weights.push(dec2.decode_symbol());
                    break Result::Ok(());
                }

                let w = dec2.decode_symbol();
                self.weights.push(w);
                match dec2.update_state(ref br) {
                    Result::Ok(()) => {},
                    Result::Err(err) => {
                        break Result::Err(HuffmanTableError::FSEDecoderError(err));
                    },
                };

                if br.bits_remaining() <= -1 {
                    self.weights.push(dec1.decode_symbol());
                    break Result::Ok(());
                }
                if self.weights.len() > 255 {
                    break Result::Err(HuffmanTableError::TooManyWeights((self.weights.len(),)));
                }
            };
            if result.is_err() {
                return Result::Err(result.unwrap_err());
            }
        } else {
            let weights_raw = source.slice(1, source.len());
            let num_weights = header - 127;
            self.weights.resize(num_weights.into(), 0);

            let bytes_needed = if num_weights % 2 == 0 {
                num_weights.into() / 2
            } else {
                (num_weights.into() / 2) + 1
            };

            if weights_raw.len() < bytes_needed {
                return Result::Err(
                    HuffmanTableError::NotEnoughBytesInSource((weights_raw.len(), bytes_needed))
                );
            }

            let mut idx: usize = 0;
            loop {
                if idx == num_weights.into() {
                    break;
                }

                if idx | 1 == 1 {
                    self.weights.set(idx, weights_raw[idx / 2] & 0xF);
                } else {
                    self.weights.set(idx, BitShift::shr(weights_raw[idx / 2], 4));
                }
                bits_read += 4;

                idx += 1;
            }
        }

        let bytes_read = if bits_read % 8 == 0 {
            bits_read / 8
        } else {
            (bits_read / 8) + 1
        };
        Result::Ok(bytes_read.into())
    }

    fn build_table_from_weights(ref self: HuffmanTable) -> Result<(), HuffmanTableError> {
        self.bits.clear();
        self.bits.resize(self.weights.len() + 1, 0);

        let mut weight_sum: u32 = 0;
        let mut i: usize = 0;
        let len = self.weights.len();
        let result = loop {
            if i == len {
                break Result::Ok(());
            }

            let weight = self.weights[i];

            if weight > MAX_MAX_NUM_BITS {
                break Result::Err(HuffmanTableError::WeightBiggerThanMaxNumBits((weight,)));
            }

            weight_sum += if weight > 0 {
                BitShift::shl(1_u32, weight.into() - 1)
            } else {
                0
            };

            i += 1;
        };
        if result.is_err() {
            return Result::Err(result.unwrap_err());
        }

        if weight_sum == 0 {
            return Result::Err(HuffmanTableError::MissingWeights);
        }

        let max_bits = weight_sum.try_into().unwrap().highest_bit_set();
        let max_bits: u8 = max_bits.try_into().unwrap();
        let left_over = BitShift::shl(1_u32, max_bits.into()) - weight_sum;

        if !left_over.is_power_of_two() {
            return Result::Err(HuffmanTableError::LeftoverIsNotAPowerOf2((left_over,)));
        }

        let last_weight = left_over.try_into().unwrap().highest_bit_set();

        let mut symbol: usize = 0;
        let len = self.weights.len();
        loop {
            if symbol == len {
                break;
            }

            let bits = if self.weights[symbol] > 0 {
                max_bits + 1 - self.weights[symbol]
            } else {
                0
            };
            self.bits.set(symbol, bits);

            symbol += 1;
        };

        self.bits.set(self.weights.len(), max_bits + 1 - last_weight.try_into().unwrap());
        self.max_num_bits = max_bits.try_into().unwrap();

        if max_bits > MAX_MAX_NUM_BITS {
            return Result::Err(HuffmanTableError::MaxBitsTooHigh((max_bits,)));
        }

        self.bit_ranks.clear();
        self.bit_ranks.resize((max_bits + 1).into(), 0);
        let mut i: usize = 0;
        let len = self.bits.len();
        loop {
            if i == len {
                break;
            }

            let num_bits: usize = self.bits[i].into();
            self.bit_ranks.set(num_bits, self.bit_ranks[num_bits] + 1);

            i += 1;
        };

        self
            .decode
            .resize(
                BitShift::shl(1_usize, self.max_num_bits.into()), Entry { symbol: 0, num_bits: 0, },
            );

        self.rank_indexes.clear();
        self.rank_indexes.resize((max_bits + 1).into(), 0);

        self.rank_indexes.set(max_bits.into(), 0);
        let mut bits: usize = self.rank_indexes.len().try_into().unwrap() - 1;
        loop {
            if bits == 0 {
                break;
            }

            self
                .rank_indexes
                .set(
                    bits - 1,
                    self.rank_indexes[bits]
                        + self.bit_ranks[bits].into() * BitShift::shl(1, (max_bits.into() - bits))
                );

            bits -= 1;
        };

        assert(self.rank_indexes[0] == self.decode.len(), 'rank_idx[0] != decode.len()');

        let mut symbol: usize = 0;
        let bits_len = self.bits.len();
        loop {
            if symbol == bits_len {
                break;
            }

            let bits_for_symbol = self.bits[symbol];
            if bits_for_symbol != 0 {
                let base_idx = self.rank_indexes[bits_for_symbol.into()];
                let len: usize = BitShift::shl(1, max_bits - bits_for_symbol).into();
                self
                    .rank_indexes
                    .set(
                        bits_for_symbol.into(),
                        self.rank_indexes[bits_for_symbol.into()] + len.try_into().unwrap()
                    );

                let mut idx: usize = 0;
                loop {
                    if idx == len {
                        break;
                    }

                    let mut entry: Entry = self.decode[base_idx + idx];
                    entry.symbol = symbol.try_into().unwrap();
                    entry.num_bits = bits_for_symbol;
                    self.decode.set(base_idx + idx, entry);

                    idx += 1;
                };
            }

            symbol += 1;
        };

        Result::Ok(())
    }
}
