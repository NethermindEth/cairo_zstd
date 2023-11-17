use byte_array::ByteArray;

use alexandria_math::{BitShift};

use cairo_zstd::decoding::bit_reader_reverse::{BitReaderReversedTrait, GetBitsError};
use cairo_zstd::decoding::scratch::HuffmanScratch;
use cairo_zstd::huff0::huff0_decoder::{
    HuffmanDecoderTrait, HuffmanTableTrait, HuffmanDecoderError, HuffmanTableError
};
use cairo_zstd::blocks::literals_section::{LiteralsSection, LiteralsSectionType};
use cairo_zstd::utils::types::isize;
use cairo_zstd::utils::byte_array::{
    ByteArraySlice, ByteArraySliceTrait, ByteArraySliceExtendTrait, ByteArrayPushResizeTrait
};
use cairo_zstd::utils::math::U8TryIntoI32;

#[derive(Drop)]
enum DecompressLiteralsError {
    MissingCompressedSize,
    MissingNumStreams,
    GetBitsError: GetBitsError,
    HuffmanTableError: HuffmanTableError,
    HuffmanDecoderError: HuffmanDecoderError,
    UninitializedHuffmanTable,
    MissingBytesForJumpHeader: (usize,),
    MissingBytesForLiterals: (usize, usize),
    ExtraPadding: (i32,),
    BitstreamReadMismatch: (isize, isize),
    DecodedLiteralCountMismatch: (usize, usize),
}

fn decode_literals(
    section: @LiteralsSection,
    ref scratch: HuffmanScratch,
    source: @ByteArraySlice,
    ref target: ByteArray,
) -> Result<u32, DecompressLiteralsError> {
    match section.ls_type {
        LiteralsSectionType::Raw => {
            target.extend_slice(@source.slice(0, *section.regenerated_size));
            Result::Ok(*section.regenerated_size)
        },
        LiteralsSectionType::RLE => {
            target.push_resize(target.len() + *section.regenerated_size, source[0]);
            Result::Ok(1)
        },
        LiteralsSectionType::Compressed => {
            let bytes_read = decompress_literals(section, ref scratch, source, ref target)?;
            Result::Ok(bytes_read)
        },
        LiteralsSectionType::Treeless => {
            let bytes_read = decompress_literals(section, ref scratch, source, ref target)?;
            Result::Ok(bytes_read)
        },
    }
}

fn decompress_literals(
    section: @LiteralsSection,
    ref scratch: HuffmanScratch,
    source: @ByteArraySlice,
    ref target: ByteArray,
) -> Result<u32, DecompressLiteralsError> {
    let compressed_size = (*section.compressed_size)
        .ok_or(DecompressLiteralsError::MissingCompressedSize)?;
    let num_streams = (*section.num_streams).ok_or(DecompressLiteralsError::MissingNumStreams)?;

    let source = @source.slice(0, compressed_size);
    let mut bytes_read = 0;

    match section.ls_type {
        LiteralsSectionType::Raw => {},
        LiteralsSectionType::RLE => {},
        LiteralsSectionType::Compressed => {
            bytes_read += match scratch.table.build_decoder(source) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    return Result::Err(DecompressLiteralsError::HuffmanTableError(err));
                },
            };
        },
        LiteralsSectionType::Treeless => {
            if scratch.table.max_num_bits == 0 {
                return Result::Err(DecompressLiteralsError::UninitializedHuffmanTable);
            }
        },
    }

    let source = source.slice(bytes_read, source.len());

    if num_streams == 4 {
        if source.len() < 6 {
            return Result::Err(DecompressLiteralsError::MissingBytesForJumpHeader((source.len(),)));
        }
        let jump1: usize = source[0].into() + BitShift::shl(source[1].into(), 8_usize);
        let jump2 = jump1 + source[2].into() + BitShift::shl(source[3].into(), 8_usize);
        let jump3 = jump2 + source[4].into() + BitShift::shl(source[5].into(), 8_usize);
        bytes_read += 6;
        let source = source.slice(6, source.len());

        if source.len() < jump3 {
            return Result::Err(
                DecompressLiteralsError::MissingBytesForLiterals((source.len(), jump3))
            );
        }

        let stream1 = @source.slice(0, jump1);
        let stream2 = @source.slice(jump1, jump2);
        let stream3 = @source.slice(jump2, jump3);
        let stream4 = @source.slice(jump3, source.len());

        _process_stream(ref scratch, ref target, stream1)?;
        _process_stream(ref scratch, ref target, stream2)?;
        _process_stream(ref scratch, ref target, stream3)?;
        _process_stream(ref scratch, ref target, stream4)?;

        bytes_read += source.len();
    } else {
        assert(num_streams == 1, 'more than one stream');
        let mut decoder = HuffmanDecoderTrait::new();
        let mut br = BitReaderReversedTrait::new(@source);
        let mut skipped_bits = 0;
        let result = loop {
            let val = match br.get_bits(1) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecompressLiteralsError::GetBitsError(err));
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
            return Result::Err(DecompressLiteralsError::ExtraPadding((skipped_bits,)));
        }

        match decoder.init_state(ref scratch.table, ref br) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(DecompressLiteralsError::HuffmanDecoderError(err));
            },
        };

        let result = loop {
            if !(br.bits_remaining() > -scratch.table.max_num_bits.into()) {
                break Result::Ok(());
            }

            target.append_byte(decoder.decode_symbol(ref scratch.table));
            match decoder.next_state(ref scratch.table, ref br) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(DecompressLiteralsError::HuffmanDecoderError(err));
                },
            };
        };

        if result.is_err() {
            return Result::Err(result.unwrap_err());
        }

        bytes_read += source.len();
    }

    if target.len() != *section.regenerated_size {
        return Result::Err(
            DecompressLiteralsError::DecodedLiteralCountMismatch(
                (target.len(), *section.regenerated_size)
            )
        );
    }

    Result::Ok(bytes_read)
}

fn _process_stream(
    ref scratch: HuffmanScratch, ref target: ByteArray, stream: @ByteArraySlice
) -> Result<(), DecompressLiteralsError> {
    let mut decoder = HuffmanDecoderTrait::new();
    let mut br = BitReaderReversedTrait::new(stream);
    let mut skipped_bits = 0;

    let result = loop {
        let val = match br.get_bits(1) {
            Result::Ok(val) => val,
            Result::Err(err) => { break Result::Err(DecompressLiteralsError::GetBitsError(err)); },
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
        return Result::Err(DecompressLiteralsError::ExtraPadding((skipped_bits,)));
    }

    match decoder.init_state(ref scratch.table, ref br) {
        Result::Ok(val) => val,
        Result::Err(err) => {
            return Result::Err(DecompressLiteralsError::HuffmanDecoderError(err));
        },
    };

    let result = loop {
        if !(br.bits_remaining() > -scratch.table.max_num_bits.into()) {
            break Result::Ok(());
        }

        target.append_byte(decoder.decode_symbol(ref scratch.table));
        match decoder.next_state(ref scratch.table, ref br) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                break Result::Err(DecompressLiteralsError::HuffmanDecoderError(err));
            },
        };
    };

    if result.is_err() {
        return Result::Err(result.unwrap_err());
    }

    if br.bits_remaining() != -(scratch.table.max_num_bits.into()) {
        return Result::Err(
            DecompressLiteralsError::BitstreamReadMismatch(
                (br.bits_remaining(), -(scratch.table.max_num_bits.into()))
            )
        );
    }

    Result::Ok(())
}
