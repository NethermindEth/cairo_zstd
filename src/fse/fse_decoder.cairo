use alexandria_math::BitShift;
use alexandria_data_structures::vec::{VecTrait, Felt252Vec, NullableVec};
use alexandria_data_structures::byte_array_ext::{ByteArrayTraitExt};

use cairo_zstd::decoding::bit_reader::{BitReaderTrait, GetBitsError};
use cairo_zstd::decoding::bit_reader_reverse::{BitReaderReversed, BitReaderReversedTrait};
use cairo_zstd::utils::math::{
    I32Felt252DictValue, HighestBitSet, HighestBitSetImpl, U64TryIntoI32, I32TryIntoU32
};
use cairo_zstd::utils::vec::{Concat, SpanIntoVec, Clear, Felt252VecClear, Reserve, Resize};
use cairo_zstd::utils::array::{ArrayPushResizeTrait, ArrayAppendSpanTrait};
use cairo_zstd::utils::byte_array::ByteArraySlice;

#[derive(Destruct)]
struct FSETable {
    decode: NullableVec<Entry>,
    accuracy_log: u8,
    symbol_probabilities: Array<i32>,
    symbol_counter: Felt252Vec<u32>,
}

impl FSETableDefault of Default<FSETable> {
    fn default() -> FSETable {
        FSETableTrait::new()
    }
}

#[derive(Drop)]
enum FSETableError {
    AccLogIsZero,
    AccLogTooBig: (u8, u8),
    ProbabilityCounterMismatch: (u32, u32),
    TooManySymbols: (usize,),
    GetBitsError: GetBitsError,
}

#[derive(Destruct)]
struct FSEDecoder {
    state: Entry,
}

#[derive(Copy, Drop)]
enum FSEDecoderError {
    GetBitsError: GetBitsError,
    TableIsUninitialized,
}

#[derive(Copy, Drop)]
struct Entry {
    base_line: u32,
    num_bits: u8,
    symbol: u8,
}

impl EntryFelt252DictValue of Felt252DictValue<Entry> {
    fn zero_default() -> Entry nopanic {
        Entry { base_line: 0, num_bits: 0, symbol: 0 }
    }
}

const ACC_LOG_OFFSET: u8 = 5;

#[generate_trait]
impl FSEDecoderImpl of FSEDecoderTrait {
    fn new(ref table: FSETable) -> FSEDecoder {
        FSEDecoder {
            state: match table.decode.get(0_usize) {
                Option::Some(val) => val,
                Option::None => Entry { base_line: 0, num_bits: 0, symbol: 0, },
            },
        }
    }

    fn decode_symbol(self: @FSEDecoder) -> u8 {
        *self.state.symbol
    }

    fn init_state(
        ref self: FSEDecoder, ref table: FSETable, ref bits: BitReaderReversed
    ) -> Result<(), FSEDecoderError> {
        if table.accuracy_log == 0 {
            return Result::Err(FSEDecoderError::TableIsUninitialized);
        }

        let reading = bits.get_bits(table.accuracy_log);
        let reading: usize = reading.unwrap().try_into().unwrap();

        self.state = table.decode.at(reading);

        Result::Ok(())
    }

    fn update_state(
        ref self: FSEDecoder, ref table: FSETable, ref bits: BitReaderReversed,
    ) -> Result<(), FSEDecoderError> {
        let num_bits = self.state.num_bits;
        let add = bits.get_bits(num_bits).unwrap();
        let base_line = self.state.base_line;
        let new_state: usize = base_line.into() + add.try_into().unwrap();
        self.state = table.decode.at(new_state);

        Result::Ok(())
    }
}

#[generate_trait]
impl FSETableImpl of FSETableTrait {
    fn new() -> FSETable {
        FSETable {
            symbol_probabilities: ArrayTrait::new(),
            symbol_counter: VecTrait::<Felt252Vec, u32>::new(),
            decode: VecTrait::<NullableVec, Entry>::new(),
            accuracy_log: 0,
        }
    }

    fn reinit_from(ref self: FSETable, ref other: FSETable) {
        self.reset();
        self.symbol_counter.concat(ref other.symbol_counter);
        self.symbol_probabilities.append_span(other.symbol_probabilities.span());
        self.decode.concat(ref other.decode);
        self.accuracy_log = other.accuracy_log;
    }

    fn reset(ref self: FSETable) {
        self.symbol_counter = VecTrait::<Felt252Vec, u32>::new();
        self.symbol_probabilities = ArrayTrait::new();
        self.decode = VecTrait::<NullableVec, Entry>::new();
        self.accuracy_log = 0;
    }

    fn build_decoder(
        ref self: FSETable, source: @ByteArraySlice, max_log: u8
    ) -> Result<usize, FSETableError> {
        self.accuracy_log = 0;

        let bytes_read = self.read_probabilities(source, max_log)?;
        self.build_decoding_table();

        Result::Ok(bytes_read)
    }

    fn build_from_probabilities(
        ref self: FSETable, acc_log: u8, probs: Span<i32>,
    ) -> Result<(), FSETableError> {
        if acc_log == 0 {
            return Result::Err(FSETableError::AccLogIsZero);
        }
        self.symbol_probabilities = ArrayTrait::new();
        self.symbol_probabilities.append_span(probs);
        self.accuracy_log = acc_log;
        self.build_decoding_table();
        Result::Ok(())
    }

    fn build_decoding_table(ref self: FSETable) {
        self.decode.clear();

        let table_size: usize = BitShift::shl(1_usize, self.accuracy_log.into());
        if self.decode.len() < table_size {
            self.decode.reserve(table_size - self.decode.len());
        }
        self.decode.resize(table_size, Entry { base_line: 0, num_bits: 0, symbol: 0, },);

        let mut negative_idx = table_size;

        let probs = self.symbol_probabilities.span();

        let mut i: u32 = 0;
        let len = probs.len();
        loop {
            if i == len {
                break;
            }

            let symbol: u8 = i.try_into().unwrap();

            if *probs[i] == -1 {
                negative_idx -= 1;
                let mut entry: Entry = self.decode[negative_idx];
                entry.symbol = symbol;
                entry.base_line = 0;
                entry.num_bits = self.accuracy_log;
                self.decode.set(negative_idx, entry);
            }

            i += 1;
        };

        let mut position = 0;
        let mut i: u32 = 0;
        let len = probs.len();

        loop {
            if i == len {
                break;
            }

            let symbol: u8 = i.try_into().unwrap();
            let prob = *probs[i];

            let mut j = 0;
            loop {
                if j == prob {
                    break;
                }

                let mut entry: Entry = self.decode[position];
                entry.symbol = symbol;
                self.decode.set(position, entry);

                position = next_position(position, table_size);

                loop {
                    if !(position >= negative_idx) {
                        break;
                    }

                    position = next_position(position, table_size);
                };

                j += 1;
            };

            i += 1;
        };

        self.symbol_counter.clear();
        self.symbol_counter.resize(self.symbol_probabilities.len(), 0);

        let mut i = 0;
        loop {
            if i == negative_idx {
                break;
            }

            let mut entry: Entry = self.decode[i];
            let symbol = entry.symbol;
            let prob = *probs[symbol.into()];

            let symbol_count = self.symbol_counter[symbol.into()];
            let (bl, nb) = calc_baseline_and_numbits(
                table_size.into(), prob.try_into().unwrap(), symbol_count
            );

            assert(nb <= self.accuracy_log, 'nb > accuracy_log');
            let counter = self.symbol_counter[symbol.into()];
            self.symbol_counter.set(symbol.into(), counter + 1);

            entry.base_line = bl;
            entry.num_bits = nb;
            self.decode.set(i, entry);

            i += 1;
        }
    }

    fn read_probabilities(
        ref self: FSETable, source: @ByteArraySlice, max_log: u8
    ) -> Result<usize, FSETableError> {
        self.symbol_probabilities = ArrayTrait::new();

        let mut br = BitReaderTrait::new(source);

        let acc_idx = br.get_bits(4);
        if acc_idx.is_err() {
            return Result::Err(FSETableError::GetBitsError(acc_idx.unwrap_err()));
        }

        self.accuracy_log = ACC_LOG_OFFSET + (acc_idx.unwrap().try_into().unwrap());
        if self.accuracy_log > max_log {
            return Result::Err(FSETableError::AccLogTooBig((self.accuracy_log, max_log)));
        }
        if self.accuracy_log == 0 {
            return Result::Err(FSETableError::AccLogIsZero);
        }

        let probablility_sum: u32 = BitShift::shl(1_u32, self.accuracy_log.into());
        let mut probability_counter: u32 = 0;

        let res1 = loop {
            if !(probability_counter < probablility_sum) {
                break Result::Ok(());
            }

            let max_remaining_value = probablility_sum - probability_counter + 1;
            let bits_to_read = max_remaining_value.try_into().unwrap().highest_bit_set();

            let unchecked_value = br.get_bits(bits_to_read.into());

            if unchecked_value.is_err() {
                break Result::Err(unchecked_value.unwrap_err());
            }

            let unchecked_value = unchecked_value.unwrap();

            let low_threshold: u64 = (BitShift::shl(1_u64, bits_to_read.into()) - 1)
                - max_remaining_value.into();
            let mask: u64 = BitShift::shl(1_u64, bits_to_read.into() - 1) - 1;
            let small_value = unchecked_value & mask;

            let value = if small_value < low_threshold {
                br.return_bits(1);
                small_value
            } else if unchecked_value > mask {
                unchecked_value - low_threshold
            } else {
                unchecked_value
            };

            let prob: i32 = value.try_into().unwrap() - 1;

            self.symbol_probabilities.append(prob);
            if prob != 0 {
                if prob > 0 {
                    probability_counter += prob.try_into().unwrap();
                } else {
                    assert(prob == -1, 'prob != -1');
                    probability_counter += 1;
                }
            } else {
                let res2 = loop {
                    let skip_amount = br.get_bits(2);

                    if skip_amount.is_err() {
                        break Result::Err(skip_amount.unwrap_err());
                    }

                    self
                        .symbol_probabilities
                        .push_resize(
                            self.symbol_probabilities.len()
                                + skip_amount.unwrap().try_into().unwrap(),
                            0
                        );

                    if skip_amount.unwrap() != 3 {
                        break Result::Ok(());
                    }
                };

                if res2.is_err() {
                    break res2;
                }
            }
        };

        if res1.is_err() {
            return Result::Err(FSETableError::GetBitsError(res1.unwrap_err()));
        }

        if probability_counter != probablility_sum {
            return Result::Err(
                FSETableError::ProbabilityCounterMismatch((probability_counter, probablility_sum))
            );
        }
        if self.symbol_probabilities.len() > 256 {
            return Result::Err(FSETableError::TooManySymbols((self.symbol_probabilities.len(),)));
        }

        let bytes_read = if br.bits_read() % 8 == 0 {
            br.bits_read() / 8
        } else {
            (br.bits_read() / 8) + 1
        };

        Result::Ok(bytes_read)
    }
}

fn next_position(mut p: usize, table_size: usize) -> usize {
    p += BitShift::shr(table_size, 1) + BitShift::shr(table_size, 3) + 3;
    p = p & (table_size - 1);
    p
}

fn calc_baseline_and_numbits(
    num_states_total: u32, num_states_symbol: u32, state_number: u32,
) -> (u32, u8) {
    let mask = BitShift::shl(1, (num_states_symbol.try_into().unwrap().highest_bit_set() - 1));

    let num_state_slices = if mask == num_states_symbol {
        num_states_symbol
    } else {
        mask
    };

    let num_double_width_state_slices = num_state_slices - num_states_symbol;
    let num_single_width_state_slices = num_states_symbol - num_double_width_state_slices;
    let slice_width = num_states_total / num_state_slices;
    let num_bits = slice_width.try_into().unwrap().highest_bit_set() - 1;

    if state_number < num_double_width_state_slices {
        let baseline = num_single_width_state_slices * slice_width + state_number * slice_width * 2;
        (baseline, num_bits.try_into().unwrap() + 1)
    } else {
        let index_shifted = state_number - num_double_width_state_slices;
        ((index_shifted * slice_width), num_bits.try_into().unwrap())
    }
}
