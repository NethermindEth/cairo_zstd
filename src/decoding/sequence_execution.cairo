use cairo_zstd::decoding::decode_buffer::{DecodeBufferTrait, DecodeBufferError};
use cairo_zstd::decoding::scratch::{DecoderScratch, DecoderScratchTrait, Sequence};
use cairo_zstd::utils::byte_array::ByteArraySliceTrait;

#[derive(Drop)]
enum ExecuteSequencesError {
    DecodeBufferError: DecodeBufferError,
    NotEnoughBytesForSequence: (usize, usize),
    ZeroOffset,
}

fn execute_sequences(ref scratch: DecoderScratch) -> Result<(), ExecuteSequencesError> {
    let mut literals_copy_counter = 0;
    let old_buffer_size = scratch.buffer.len();
    let mut seq_sum = 0;

    let sequences = @scratch.sequences;

    let len = sequences.len();
    let mut i: usize = 0;
    let result = loop {
        if i >= len {
            break Result::Ok(());
        }

        let seq = *sequences.at(i);

        if seq.literals_length > 0 {
            let high = literals_copy_counter + seq.literals_length;
            if high > scratch.literals_buffer.len() {
                break Result::Err(
                    ExecuteSequencesError::NotEnoughBytesForSequence(
                        (high, scratch.literals_buffer.len())
                    )
                );
            }
            let literals = scratch.literals_buffer.slice(literals_copy_counter, high);
            literals_copy_counter += seq.literals_length.into();

            scratch.buffer.push(literals);
        }

        let (actual_offset, new_scratch) = do_offset_history(
            seq.offset, seq.literals_length, scratch.offset_hist
        );
        let (actual_offset, new_scratch) = (0_u32, (0_u32, 0_u32, 0_u32));
        if actual_offset == 0 {
            break Result::Err(ExecuteSequencesError::ZeroOffset);
        }

        scratch.offset_hist = new_scratch;

        if seq.match_length > 0 {
            match scratch.buffer.repeat(actual_offset.into(), seq.match_length.into()) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(ExecuteSequencesError::DecodeBufferError(err));
                },
            }
        }

        seq_sum += seq.match_length;
        seq_sum += seq.literals_length;

        i += 1;
    };

    if result.is_err() {
        return Result::Err(result.unwrap_err());
    }

    if literals_copy_counter < scratch.literals_buffer.len() {
        let rest_literals = scratch
            .literals_buffer
            .slice(literals_copy_counter, scratch.literals_buffer.len());
        scratch.buffer.push(rest_literals);
        seq_sum += rest_literals.len();
    }

    let diff = scratch.buffer.len() - old_buffer_size;
    assert(seq_sum.into() == diff, 'seq_sum != buffersize diff');
    Result::Ok(())
}

fn do_offset_history(
    offset_value: u32, lit_len: u32, scratch: (u32, u32, u32)
) -> (u32, (u32, u32, u32)) {
    let (scratch0, scratch1, scratch2) = scratch;

    let actual_offset = if lit_len > 0 {
        if offset_value == 1 {
            scratch0
        } else if offset_value == 2 {
            scratch1
        } else if offset_value == 3 {
            scratch2
        } else {
            offset_value - 3
        }
    } else {
        if offset_value == 1 {
            scratch1
        } else if offset_value == 2 {
            scratch2
        } else if offset_value == 3 {
            scratch0 - 1
        } else {
            offset_value - 3
        }
    };

    let new_scratch = if lit_len > 0 {
        if offset_value == 1 {
            scratch
        } else if offset_value == 2 {
            (actual_offset, scratch0, scratch2)
        } else {
            (actual_offset, scratch0, scratch1)
        }
    } else {
        if offset_value == 1 {
            (actual_offset, scratch0, scratch2)
        } else {
            (actual_offset, scratch0, scratch1)
        }
    };

    (actual_offset, new_scratch)
}
