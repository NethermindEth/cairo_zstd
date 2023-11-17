use alexandria_math::BitShift;

use cairo_zstd::blocks::block::{BlockHeader, BlockType};
use cairo_zstd::blocks::literals_section::{
    LiteralsSectionTrait, LiteralsSectionType, LiteralsSectionParseError
};
use cairo_zstd::blocks::sequence_section::{
    SequencesHeader, SequencesHeaderTrait, SequencesHeaderParseError
};
use cairo_zstd::decoding::literals_section_decoder::{decode_literals, DecompressLiteralsError};
use cairo_zstd::decoding::sequence_execution::ExecuteSequencesError;
use cairo_zstd::decoding::sequence_section_decoder::decode_sequences;
use cairo_zstd::decoding::sequence_section_decoder::DecodeSequenceError;
use cairo_zstd::decoding::scratch::DecoderScratch;
use cairo_zstd::decoding::sequence_execution::execute_sequences;
use cairo_zstd::decoding::decode_buffer::DecodeBufferTrait;
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait, ByteArraySliceExtendTrait};

#[derive(Drop)]
struct BlockDecoder {
    header_buffer: (u8, u8, u8),
    internal_state: DecoderState,
}

#[derive(Drop, Copy)]
enum DecoderState {
    ReadyToDecodeNextHeader,
    ReadyToDecodeNextBody,
    Failed,
}

#[derive(Drop)]
enum BlockHeaderReadError {
    FoundReservedBlock,
    BlockTypeError: BlockTypeError,
    BlockSizeError: BlockSizeError,
}

#[derive(Drop)]
enum BlockTypeError {
    InvalidBlocktypeNumber: (u8,),
}

#[derive(Drop)]
enum BlockSizeError {
    BlockSizeTooLarge: (u32,),
}

#[derive(Drop)]
enum DecompressBlockError {
    MalformedSectionHeader: (usize, usize),
    DecompressLiteralsError: DecompressLiteralsError,
    LiteralsSectionParseError: LiteralsSectionParseError,
    SequencesHeaderParseError: SequencesHeaderParseError,
    DecodeSequenceError: DecodeSequenceError,
    ExecuteSequencesError: ExecuteSequencesError,
}

#[derive(Drop)]
enum DecodeBlockContentError {
    DecoderStateIsFailed,
    ExpectedHeaderOfPreviousBlock,
    ReservedBlock,
    DecompressBlockError: DecompressBlockError,
}

const ABSOLUTE_MAXIMUM_BLOCK_SIZE: u32 = consteval_int!(128 * 1024);

#[generate_trait]
impl BlockDecoderImpl of BlockDecoderTrait {
    fn new() -> BlockDecoder {
        BlockDecoder {
            internal_state: DecoderState::ReadyToDecodeNextHeader, header_buffer: (0, 0, 0),
        }
    }

    fn decode_block_content(
        ref self: BlockDecoder,
        header: @BlockHeader,
        ref workspace: DecoderScratch,
        ref source: @ByteArraySlice,
    ) -> Result<u64, DecodeBlockContentError> {
        let state = @self.internal_state;

        match *state {
            DecoderState::ReadyToDecodeNextHeader => {
                return Result::Err(DecodeBlockContentError::ExpectedHeaderOfPreviousBlock);
            },
            DecoderState::ReadyToDecodeNextBody => {},
            DecoderState::Failed => {
                return Result::Err(DecodeBlockContentError::DecoderStateIsFailed);
            },
        }

        let block_type = header.block_type;
        match block_type {
            BlockType::Raw => {
                workspace.buffer.push(@source.slice(0, *header.decompressed_size));
                source = @source.slice(*header.decompressed_size, source.len());

                self.internal_state = DecoderState::ReadyToDecodeNextHeader;
                Result::Ok((*header.decompressed_size).into())
            },
            BlockType::RLE => {
                let byte = source.at(0).unwrap();
                source = @source.slice(1, source.len());

                self.internal_state = DecoderState::ReadyToDecodeNextHeader;

                let mut i: usize = 0;
                let len = *header.decompressed_size;
                loop {
                    if i >= len {
                        break;
                    }

                    workspace.buffer.append_byte(byte);

                    i += 1;
                };

                Result::Ok(1)
            },
            BlockType::Compressed => {
                match self.decompress_block(header, ref workspace, ref source) {
                    Result::Ok(()) => {},
                    Result::Err(err) => {
                        return Result::Err(DecodeBlockContentError::DecompressBlockError(err));
                    },
                }

                self.internal_state = DecoderState::ReadyToDecodeNextHeader;
                Result::Ok((*header.content_size).into())
            },
            BlockType::Reserved => { Result::Err(DecodeBlockContentError::ReservedBlock) },
        }
    }

    fn decompress_block(
        ref self: BlockDecoder,
        header: @BlockHeader,
        ref workspace: DecoderScratch,
        ref source: @ByteArraySlice,
    ) -> Result<(), DecompressBlockError> {
        workspace.block_content_buffer = source.slice(0, (*header.content_size).into());
        source = @source.slice((*header.content_size).into(), source.len());

        let raw = @workspace.block_content_buffer;

        let mut section = LiteralsSectionTrait::new();
        let bytes_in_literals_header = match section.parse_from_header(raw) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(DecompressBlockError::LiteralsSectionParseError(err));
            },
        };

        let raw = @raw.slice(bytes_in_literals_header.into(), raw.len());

        let upper_limit_for_literals = match section.compressed_size {
            Option::Some(x) => x.into(),
            Option::None => {
                if section.ls_type == LiteralsSectionType::RLE {
                    1
                } else if section.ls_type == LiteralsSectionType::Raw {
                    section.regenerated_size.into()
                } else {
                    panic_with_felt252('Bug in this library');
                    0
                }
            },
        };

        if raw.len() < upper_limit_for_literals {
            return Result::Err(
                DecompressBlockError::MalformedSectionHeader((upper_limit_for_literals, raw.len()))
            );
        }

        let raw_literals = @raw.slice(0, upper_limit_for_literals);

        let mut literals_buffer: ByteArray = Default::default();

        let bytes_used_in_literals_section =
            match decode_literals(@section, ref workspace.huf, raw_literals, ref literals_buffer) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(DecompressBlockError::DecompressLiteralsError(err));
            },
        };
        workspace
            .literals_buffer = ByteArraySliceTrait::new(@literals_buffer, 0, literals_buffer.len());

        assert(bytes_used_in_literals_section == upper_limit_for_literals.into(), '');

        let raw = @raw.slice(upper_limit_for_literals, raw.len());

        let mut seq_section = SequencesHeaderTrait::new();
        let bytes_in_sequence_header = match seq_section.parse_from_header(raw) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(DecompressBlockError::SequencesHeaderParseError(err));
            },
        };

        let raw = @raw.slice(bytes_in_sequence_header.into(), raw.len());

        assert(
            bytes_in_literals_header.into()
                + bytes_used_in_literals_section
                + bytes_in_sequence_header.into()
                + raw.len() == *header.content_size,
            ''
        );

        if seq_section.num_sequences != 0 {
            match decode_sequences(@seq_section, raw, ref workspace.fse, ref workspace.sequences) {
                Result::Ok(()) => {},
                Result::Err(err) => {
                    return Result::Err(DecompressBlockError::DecodeSequenceError(err));
                },
            };
            match execute_sequences(ref workspace) {
                Result::Ok(()) => {},
                Result::Err(err) => {
                    return Result::Err(DecompressBlockError::ExecuteSequencesError(err));
                },
            };
        } else {
            workspace.buffer.push(@workspace.literals_buffer);
            workspace.sequences = ArrayTrait::new();
        }

        Result::Ok(())
    }

    fn read_block_header(
        ref self: BlockDecoder, ref r: @ByteArraySlice,
    ) -> Result<(BlockHeader, u8), BlockHeaderReadError> {
        let header = r.slice(0, 3);
        self.header_buffer = (header[0], header[1], header[2]);
        r = @r.slice(3, r.len());

        let btype = match self.block_type() {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(BlockHeaderReadError::BlockTypeError(err)); },
        };
        if btype == BlockType::Reserved {
            return Result::Err(BlockHeaderReadError::FoundReservedBlock);
        }

        let block_size = match self.block_content_size() {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(BlockHeaderReadError::BlockSizeError(err)); },
        };
        let decompressed_size = match btype {
            BlockType::Raw => block_size,
            BlockType::RLE => block_size,
            BlockType::Compressed => 0,
            BlockType::Reserved => 0,
        };
        let content_size = match btype {
            BlockType::Raw => block_size,
            BlockType::RLE => 1,
            BlockType::Compressed => block_size,
            BlockType::Reserved => 0,
        };

        let last_block = self.is_last();

        self.reset_buffer();
        self.internal_state = DecoderState::ReadyToDecodeNextBody;

        //just return 3. Blockheaders always take 3 bytes
        Result::Ok(
            (BlockHeader { last_block, block_type: btype, decompressed_size, content_size, }, 3,)
        )
    }

    fn reset_buffer(ref self: BlockDecoder) {
        self.header_buffer = (0, 0, 0);
    }

    fn is_last(self: @BlockDecoder) -> bool {
        let (a, _, _) = *self.header_buffer;
        a & 0x1 == 1
    }

    fn block_type(self: @BlockDecoder) -> Result<BlockType, BlockTypeError> {
        let (a, _, _) = *self.header_buffer;
        let t = BitShift::shr(a, 1) & 0x3;

        if t == 0 {
            Result::Ok(BlockType::Raw)
        } else if t == 1 {
            Result::Ok(BlockType::RLE)
        } else if t == 2 {
            Result::Ok(BlockType::Compressed)
        } else if t == 3 {
            Result::Ok(BlockType::Reserved)
        } else {
            Result::Err(BlockTypeError::InvalidBlocktypeNumber((t,)))
        }
    }

    fn block_content_size(self: @BlockDecoder) -> Result<u32, BlockSizeError> {
        let val = self.block_content_size_unchecked();
        if val > ABSOLUTE_MAXIMUM_BLOCK_SIZE {
            Result::Err(BlockSizeError::BlockSizeTooLarge((val,)))
        } else {
            Result::Ok(val)
        }
    }

    fn block_content_size_unchecked(self: @BlockDecoder) -> u32 {
        let (a, b, c) = *self.header_buffer;

        BitShift::shr(a.into(), 3_u32)
            | BitShift::shl(b.into(), 5_u32)
            | BitShift::shl(c.into(), 13_u32)
    }
}
