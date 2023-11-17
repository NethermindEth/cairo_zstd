use array::ArrayTrait;

use alexandria_math::BitShift;

use cairo_zstd::blocks::sequence_section::{
    Sequence, SequencesHeader, ModeType, CompressionModesTrait
};
use cairo_zstd::decoding::bit_reader_reverse::{
    BitReaderReversed, BitReaderReversedTrait, GetBitsError
};
use cairo_zstd::decoding::scratch::FSEScratch;
use cairo_zstd::fse::fse_decoder::{
    FSEDecoder, FSEDecoderTrait, FSEDecoderError, FSETableTrait, FSETableError
};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};
use cairo_zstd::utils::types::isize;
use cairo_zstd::utils::math::{I32TryIntoU64};

#[derive(Drop)]
enum DecodeSequenceError {
    GetBitsError: GetBitsError,
    FSEDecoderError: FSEDecoderError,
    FSETableError: FSETableError,
    ExtraPadding: (i32,),
    UnsupportedOffset: (u8,),
    ZeroOffset,
    NotEnoughBytesForNumSequences,
    ExtraBits: (isize,),
    MissingCompressionMode,
    MissingByteForRleLlTable,
    MissingByteForRleOfTable,
    MissingByteForRleMlTable,
}

fn decode_sequences(
    section: @SequencesHeader,
    source: @ByteArraySlice,
    ref scratch: FSEScratch,
    ref target: Array<Sequence>,
) -> Result<(), DecodeSequenceError> {
    let bytes_read = maybe_update_fse_tables(section, source, ref scratch)?;
    let bit_stream = @source.slice(bytes_read, source.len());

    let mut br = BitReaderReversedTrait::new(bit_stream);

    let mut skipped_bits = 0;
    let result = loop {
        let val = match br.get_bits(1) {
            Result::Ok(val) => val,
            Result::Err(err) => { break Result::Err(DecodeSequenceError::GetBitsError(err)); },
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
        return Result::Err(DecodeSequenceError::ExtraPadding((skipped_bits,)));
    }

    if scratch.ll_rle.is_some() || scratch.ml_rle.is_some() || scratch.of_rle.is_some() {
        decode_sequences_with_rle(section, ref br, ref scratch, ref target)
    } else {
        decode_sequences_without_rle(section, ref br, ref scratch, ref target)
    }
}

fn decode_sequences_with_rle(
    section: @SequencesHeader,
    ref br: BitReaderReversed,
    ref scratch: FSEScratch,
    ref target: Array<Sequence>,
) -> Result<(), DecodeSequenceError> {
    let mut ll_dec = FSEDecoderTrait::new(ref scratch.literal_lengths);
    let mut ml_dec = FSEDecoderTrait::new(ref scratch.match_lengths);
    let mut of_dec = FSEDecoderTrait::new(ref scratch.offsets);

    if scratch.ll_rle.is_none() {
        match ll_dec.init_state(ref scratch.literal_lengths, ref br) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(DecodeSequenceError::FSEDecoderError(err)); },
        };
    }
    if scratch.of_rle.is_none() {
        match of_dec.init_state(ref scratch.offsets, ref br) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(DecodeSequenceError::FSEDecoderError(err)); },
        };
    }
    if scratch.ml_rle.is_none() {
        match ml_dec.init_state(ref scratch.match_lengths, ref br) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(DecodeSequenceError::FSEDecoderError(err)); },
        };
    }

    target = ArrayTrait::new();

    let mut _seq_idx: usize = 0;
    let result = loop {
        if _seq_idx >= *section.num_sequences {
            break Result::Ok(());
        }

        let ll_code = if scratch.ll_rle.is_some() {
            scratch.ll_rle.unwrap()
        } else {
            ll_dec.decode_symbol()
        };
        let ml_code = if scratch.ml_rle.is_some() {
            scratch.ml_rle.unwrap()
        } else {
            ml_dec.decode_symbol()
        };
        let of_code = if scratch.of_rle.is_some() {
            scratch.of_rle.unwrap()
        } else {
            of_dec.decode_symbol()
        };

        let (ll_value, ll_num_bits) = lookup_ll_code(ll_code);
        let (ml_value, ml_num_bits) = lookup_ml_code(ml_code);

        if of_code >= 32 {
            break Result::Err(DecodeSequenceError::UnsupportedOffset((of_code,)));
        }

        let (obits, ml_add, ll_add) = match br.get_bits_triple(of_code, ml_num_bits, ll_num_bits) {
            Result::Ok(val) => val,
            Result::Err(err) => { break Result::Err(DecodeSequenceError::GetBitsError(err)); },
        };
        let offset = obits.try_into().unwrap() + BitShift::shl(1_u32, of_code.into());

        if offset == 0 {
            break Result::Err(DecodeSequenceError::ZeroOffset);
        }

        target
            .append(
                Sequence {
                    literals_length: ll_value + ll_add.try_into().unwrap(),
                    match_length: ml_value + ml_add.try_into().unwrap(),
                    offset: offset,
                }
            );

        if target.len() < *section.num_sequences.into() {
            match ll_dec.update_state(ref scratch.literal_lengths, ref br) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecodeSequenceError::FSEDecoderError(err));
                },
            };
            match ml_dec.update_state(ref scratch.match_lengths, ref br) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecodeSequenceError::FSEDecoderError(err));
                },
            };
            match of_dec.update_state(ref scratch.offsets, ref br) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecodeSequenceError::FSEDecoderError(err));
                },
            };
        }

        if br.bits_remaining() < 0 {
            break Result::Err(DecodeSequenceError::NotEnoughBytesForNumSequences);
        }

        _seq_idx += 1;
    };

    if result.is_err() {
        return Result::Err(result.unwrap_err());
    }

    if br.bits_remaining() > 0 {
        Result::Err(DecodeSequenceError::ExtraBits((br.bits_remaining(),)))
    } else {
        Result::Ok(())
    }
}

fn decode_sequences_without_rle(
    section: @SequencesHeader,
    ref br: BitReaderReversed,
    ref scratch: FSEScratch,
    ref target: Array<Sequence>,
) -> Result<(), DecodeSequenceError> {
    let mut ll_dec = FSEDecoderTrait::new(ref scratch.literal_lengths);
    let mut ml_dec = FSEDecoderTrait::new(ref scratch.match_lengths);
    let mut of_dec = FSEDecoderTrait::new(ref scratch.offsets);

    match ll_dec.init_state(ref scratch.literal_lengths, ref br) {
        Result::Ok(val) => val,
        Result::Err(err) => { return Result::Err(DecodeSequenceError::FSEDecoderError(err)); },
    };
    match of_dec.init_state(ref scratch.offsets, ref br) {
        Result::Ok(val) => val,
        Result::Err(err) => { return Result::Err(DecodeSequenceError::FSEDecoderError(err)); },
    };
    match ml_dec.init_state(ref scratch.match_lengths, ref br) {
        Result::Ok(val) => val,
        Result::Err(err) => { return Result::Err(DecodeSequenceError::FSEDecoderError(err)); },
    };

    target = ArrayTrait::new();

    let mut _seq_idx: usize = 0;
    let result = loop {
        if _seq_idx >= *section.num_sequences {
            break Result::Ok(());
        }

        let ll_code = ll_dec.decode_symbol();
        let ml_code = ml_dec.decode_symbol();
        let of_code = of_dec.decode_symbol();

        let (ll_value, ll_num_bits) = lookup_ll_code(ll_code);
        let (ml_value, ml_num_bits) = lookup_ml_code(ml_code);

        if of_code >= 32 {
            break Result::Err(DecodeSequenceError::UnsupportedOffset((of_code,)));
        }

        let (obits, ml_add, ll_add) = match br.get_bits_triple(of_code, ml_num_bits, ll_num_bits) {
            Result::Ok(val) => val,
            Result::Err(err) => { break Result::Err(DecodeSequenceError::GetBitsError(err)); },
        };
        let offset = obits.try_into().unwrap() + BitShift::shl(1_u32, of_code.into());

        if offset == 0 {
            break Result::Err(DecodeSequenceError::ZeroOffset);
        }

        target
            .append(
                Sequence {
                    literals_length: ll_value + ll_add.try_into().unwrap(),
                    match_length: ml_value + ml_add.try_into().unwrap(),
                    offset: offset,
                }
            );

        if target.len() < *section.num_sequences.into() {
            match ll_dec.update_state(ref scratch.literal_lengths, ref br) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecodeSequenceError::FSEDecoderError(err));
                },
            };
            match ml_dec.update_state(ref scratch.match_lengths, ref br) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecodeSequenceError::FSEDecoderError(err));
                },
            };
            match of_dec.update_state(ref scratch.offsets, ref br) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecodeSequenceError::FSEDecoderError(err));
                },
            };
        }

        let a: u64 = br.bits_remaining().try_into().unwrap();

        if br.bits_remaining() < 0 {
            break Result::Err(DecodeSequenceError::NotEnoughBytesForNumSequences);
        }

        _seq_idx += 1;
    };

    if result.is_err() {
        return Result::Err(result.unwrap_err());
    }

    if br.bits_remaining() > 0 {
        Result::Err(DecodeSequenceError::ExtraBits((br.bits_remaining(),)))
    } else {
        Result::Ok(())
    }
}

fn lookup_ll_code(code: u8) -> (u32, u8) {
    if code <= 15 {
        (code.into(), 0)
    } else if code == 16 {
        (16, 1)
    } else if code == 17 {
        (18, 1)
    } else if code == 18 {
        (20, 1)
    } else if code == 19 {
        (22, 1)
    } else if code == 20 {
        (24, 2)
    } else if code == 21 {
        (28, 2)
    } else if code == 22 {
        (32, 3)
    } else if code == 23 {
        (40, 3)
    } else if code == 24 {
        (48, 4)
    } else if code == 25 {
        (64, 6)
    } else if code == 26 {
        (128, 7)
    } else if code == 27 {
        (256, 8)
    } else if code == 28 {
        (512, 9)
    } else if code == 29 {
        (1024, 10)
    } else if code == 30 {
        (2048, 11)
    } else if code == 31 {
        (4096, 12)
    } else if code == 32 {
        (8192, 13)
    } else if code == 33 {
        (16384, 14)
    } else if code == 34 {
        (32768, 15)
    } else if code == 35 {
        (65536, 16)
    } else {
        (0, 255)
    }
}

fn lookup_ml_code(code: u8) -> (u32, u8) {
    if code <= 31 {
        (code.into() + 3, 0)
    } else if code == 32 {
        (35, 1)
    } else if code == 33 {
        (37, 1)
    } else if code == 34 {
        (39, 1)
    } else if code == 35 {
        (41, 1)
    } else if code == 36 {
        (43, 2)
    } else if code == 37 {
        (47, 2)
    } else if code == 38 {
        (51, 3)
    } else if code == 39 {
        (59, 3)
    } else if code == 40 {
        (67, 4)
    } else if code == 41 {
        (83, 4)
    } else if code == 42 {
        (99, 5)
    } else if code == 43 {
        (131, 7)
    } else if code == 44 {
        (259, 8)
    } else if code == 45 {
        (515, 9)
    } else if code == 46 {
        (1027, 10)
    } else if code == 47 {
        (2051, 11)
    } else if code == 48 {
        (4099, 12)
    } else if code == 49 {
        (8195, 13)
    } else if code == 50 {
        (16387, 14)
    } else if code == 51 {
        (32771, 15)
    } else if code == 52 {
        (65539, 16)
    } else {
        (0, 255)
    }
}

const LL_MAX_LOG: u8 = 9;
const ML_MAX_LOG: u8 = 9;
const OF_MAX_LOG: u8 = 8;

const LL_DEFAULT_ACC_LOG: u8 = 6;
const ML_DEFAULT_ACC_LOG: u8 = 6;
const OF_DEFAULT_ACC_LOG: u8 = 5;

fn maybe_update_fse_tables(
    section: @SequencesHeader, source: @ByteArraySlice, ref scratch: FSEScratch,
) -> Result<usize, DecodeSequenceError> {
    let modes = (*section.modes).ok_or(DecodeSequenceError::MissingCompressionMode)?;

    let mut bytes_read = 0;

    match modes.ll_mode() {
        ModeType::Predefined => {
            match scratch
                .literal_lengths
                .build_from_probabilities(
                    LL_DEFAULT_ACC_LOG,
                    array![
                        4_i32,
                        3_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        3_i32,
                        2_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                    ]
                        .span(),
                ) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    return Result::Err(DecodeSequenceError::FSETableError(err));
                },
            }
            scratch.ll_rle = Option::None;
        },
        ModeType::RLE => {
            if source.len() == 0 {
                return Result::Err(DecodeSequenceError::MissingByteForRleLlTable);
            }
            bytes_read += 1;
            scratch.ll_rle = Option::Some(source[0]);
        },
        ModeType::FSECompressed => {
            let bytes = match scratch.literal_lengths.build_decoder(source, LL_MAX_LOG) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    return Result::Err(DecodeSequenceError::FSETableError(err));
                },
            };
            bytes_read += bytes;

            scratch.ll_rle = Option::None;
        },
        ModeType::Repeat => {},
    };

    let of_source = @source.slice(bytes_read, source.len());

    match modes.of_mode() {
        ModeType::Predefined => {
            match scratch
                .offsets
                .build_from_probabilities(
                    OF_DEFAULT_ACC_LOG,
                    array![
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                    ]
                        .span(),
                ) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    return Result::Err(DecodeSequenceError::FSETableError(err));
                },
            };
            scratch.of_rle = Option::None;
        },
        ModeType::RLE => {
            if of_source.len() == 0 {
                return Result::Err(DecodeSequenceError::MissingByteForRleOfTable);
            }
            bytes_read += 1;
            scratch.of_rle = Option::Some(of_source[0]);
        },
        ModeType::FSECompressed => {
            let bytes = match scratch.offsets.build_decoder(of_source, OF_MAX_LOG) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    return Result::Err(DecodeSequenceError::FSETableError(err));
                },
            };
            bytes_read += bytes;
            scratch.of_rle = Option::None;
        },
        ModeType::Repeat => {},
    };

    let ml_source = @source.slice(bytes_read, source.len());

    match modes.ml_mode() {
        ModeType::Predefined => {
            match scratch
                .match_lengths
                .build_from_probabilities(
                    ML_DEFAULT_ACC_LOG,
                    array![
                        1_i32,
                        4_i32,
                        3_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        2_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                        -1_i32,
                    ]
                        .span(),
                ) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    return Result::Err(DecodeSequenceError::FSETableError(err));
                },
            };
            scratch.ml_rle = Option::None;
        },
        ModeType::RLE => {
            if ml_source.len() == 0 {
                return Result::Err(DecodeSequenceError::MissingByteForRleMlTable);
            }
            bytes_read += 1;
            scratch.ml_rle = Option::Some(ml_source[0]);
        },
        ModeType::FSECompressed => {
            let bytes = match scratch.match_lengths.build_decoder(ml_source, ML_MAX_LOG) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    return Result::Err(DecodeSequenceError::FSETableError(err));
                },
            };
            bytes_read += bytes;
            scratch.ml_rle = Option::None;
        },
        ModeType::Repeat => {},
    };

    Result::Ok(bytes_read)
}

#[cfg(test)]
mod tests {
    use alexandria_data_structures::vec::VecTrait;

    use cairo_zstd::fse::fse_decoder::Entry;

    use super::{FSETableTrait, LL_DEFAULT_ACC_LOG};

    #[test]
    #[available_gas(200000000000)]
    fn test_ll_default() {
        let mut table = FSETableTrait::new();

        table
            .build_from_probabilities(
                LL_DEFAULT_ACC_LOG,
                array![
                    4_i32,
                    3_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    1_i32,
                    1_i32,
                    1_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    2_i32,
                    3_i32,
                    2_i32,
                    1_i32,
                    1_i32,
                    1_i32,
                    1_i32,
                    1_i32,
                    -1_i32,
                    -1_i32,
                    -1_i32,
                    -1_i32,
                ]
                    .span(),
            )
            .unwrap();

        assert(table.decode.len() == 64, '');

        let entry: Entry = table.decode[0];

        assert(entry.symbol == 0, '');
        assert(entry.num_bits == 4, '');
        assert(entry.base_line == 0, '');

        let entry: Entry = table.decode[19];

        assert(entry.symbol == 27, '');
        assert(entry.num_bits == 6, '');
        assert(entry.base_line == 0, '');

        let entry: Entry = table.decode[39];

        assert(entry.symbol == 25, '');
        assert(entry.num_bits == 4, '');
        assert(entry.base_line == 16, '');

        let entry: Entry = table.decode[60];

        assert(entry.symbol == 35, '');
        assert(entry.num_bits == 6, '');
        assert(entry.base_line == 0, '');

        let entry: Entry = table.decode[59];

        assert(entry.symbol == 24, '');
        assert(entry.num_bits == 5, '');
        assert(entry.base_line == 32, '');
    }
}
