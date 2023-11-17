use alexandria_data_structures::vec::{VecTrait, Felt252Vec, NullableVec};

use cairo_zstd::frame::{
    ReadFrameHeaderError, FrameHeaderError, Frame, FrameHeader, FrameHeaderTrait,
    FrameDescriptorTrait, read_frame_header
};
use cairo_zstd::decoding::dictionary::{Dictionary, DictionaryTrait, DictionaryDecodeError};
use cairo_zstd::decoding::scratch::{DecoderScratch, DecoderScratchTrait};
use cairo_zstd::decoding::decode_buffer::DecodeBufferTrait;
use cairo_zstd::decoding::block_decoder::{
    BlockDecoderTrait, BlockHeaderReadError, DecodeBlockContentError
};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait, ByteArrayTraitExtRead};
use cairo_zstd::utils::xxhash64::XxHash64Trait;

#[derive(Destruct)]
struct FrameDecoder {
    state: FrameDecoderState,
}

#[derive(Destruct)]
struct FrameDecoderState {
    frame: Frame,
    decoder_scratch: DecoderScratch,
    frame_finished: bool,
    block_counter: usize,
    bytes_read_counter: u64,
    check_sum: Option<u32>,
    using_dict: Option<u32>,
}

#[derive(Copy, Drop)]
enum BlockDecodingStrategy {
    All,
    UptoBlocks: usize,
    UptoBytes: usize,
}

#[derive(Drop)]
enum FrameDecoderError {
    ReadFrameHeaderError: ReadFrameHeaderError,
    FrameHeaderError: FrameHeaderError,
    WindowSizeTooBig: (u64,),
    DictionaryDecodeError: DictionaryDecodeError,
    FailedToReadBlockHeader: BlockHeaderReadError,
    FailedToReadBlockBody: DecodeBlockContentError,
    TargetTooSmall,
}

const MAX_WINDOW_SIZE: u64 = consteval_int!(1024 * 1024 * 100);

#[generate_trait]
impl FrameDecoderStateImpl of FrameDecoderStateTrait {
    fn new(ref source: @ByteArraySlice) -> Result<FrameDecoderState, FrameDecoderError> {
        let (frame, header_size) = match read_frame_header(ref source) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(FrameDecoderError::ReadFrameHeaderError(err));
            },
        };
        let window_size = match frame.header.window_size() {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(FrameDecoderError::FrameHeaderError(err)); },
        };
        Result::Ok(
            FrameDecoderState {
                frame,
                frame_finished: false,
                block_counter: 0,
                decoder_scratch: DecoderScratchTrait::new(window_size.try_into().unwrap()),
                bytes_read_counter: header_size.into(),
                check_sum: Option::None,
                using_dict: Option::None,
            }
        )
    }

    fn reset(
        ref self: FrameDecoderState, ref source: @ByteArraySlice
    ) -> Result<(), FrameDecoderError> {
        let (frame, header_size) = match read_frame_header(ref source) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(FrameDecoderError::ReadFrameHeaderError(err));
            },
        };
        let window_size = match frame.header.window_size() {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(FrameDecoderError::FrameHeaderError(err)); },
        };

        if window_size > MAX_WINDOW_SIZE {
            return Result::Err(FrameDecoderError::WindowSizeTooBig((window_size,)));
        }

        self.frame = frame;
        self.frame_finished = false;
        self.block_counter = 0;
        self.decoder_scratch.reset(window_size.try_into().unwrap());
        self.bytes_read_counter = header_size.into();
        self.check_sum = Option::None;
        self.using_dict = Option::None;
        Result::Ok(())
    }
}

#[generate_trait]
impl FrameDecoderImpl of FrameDecoderTrait {
    fn new(state: FrameDecoderState) -> FrameDecoder {
        FrameDecoder { state }
    }

    fn init(ref self: FrameDecoder, state: FrameDecoderState) -> Result<(), FrameDecoderError> {
        self.reset(state)
    }

    fn reset(
        ref self: FrameDecoder, mut state: FrameDecoderState
    ) -> Result<(), FrameDecoderError> {
        self.state = state;

        Result::Ok(())
    }

    fn content_size(self: @FrameDecoder) -> u64 {
        self.state.frame.header.frame_content_size()
    }

    fn get_checksum_from_data(self: @FrameDecoder) -> Option<u32> {
        *self.state.check_sum
    }

    fn get_calculated_checksum(self: @FrameDecoder) -> Option<u32> {
        let cksum_64bit: u64 = self.state.decoder_scratch.buffer.hash.digest();
        let cksum_32bit: u32 = (cksum_64bit % 0x100000000).try_into().unwrap();

        Option::Some(cksum_32bit)
    }

    fn bytes_read_from_source(self: @FrameDecoder) -> u64 {
        *self.state.bytes_read_counter
    }

    fn is_finished(self: @FrameDecoder) -> bool {
        if self.state.frame.header.descriptor.content_checksum_flag() {
            *self.state.frame_finished && self.state.check_sum.is_some()
        } else {
            *self.state.frame_finished
        }
    }

    fn blocks_decoded(self: @FrameDecoder) -> usize {
        *self.state.block_counter
    }

    fn decode_blocks(
        ref self: FrameDecoder, ref source: @ByteArraySlice, strat: BlockDecodingStrategy,
    ) -> Result<bool, FrameDecoderError> {
        let state = self.state;

        let mut block_dec = BlockDecoderTrait::new();

        let buffer_size_before = self.state.decoder_scratch.buffer.len();
        let block_counter_before = self.state.block_counter;
        let result = loop {
            let (block_header, block_header_size) = match block_dec.read_block_header(ref source) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(FrameDecoderError::FailedToReadBlockHeader(err));
                },
            };

            self.state.bytes_read_counter += block_header_size.into();

            let bytes_read_in_block_body =
                match block_dec
                    .decode_block_content(
                        @block_header, ref self.state.decoder_scratch, ref source
                    ) {
                Result::Ok(val) => val,
                Result::Err(err) => {
                    break Result::Err(FrameDecoderError::FailedToReadBlockBody(err));
                },
            };
            self.state.bytes_read_counter += bytes_read_in_block_body;

            self.state.block_counter += 1;

            if block_header.last_block {
                self.state.frame_finished = true;
                if self.state.frame.header.descriptor.content_checksum_flag() {
                    let checksum = source.slice(0, 4);
                    source = @source.slice(4, source.len());
                    self.state.bytes_read_counter += 4;

                    let checksum = checksum.word_u32_le(0).unwrap();
                    self.state.check_sum = Option::Some(checksum);
                }
                break Result::Ok(());
            }

            match strat {
                BlockDecodingStrategy::All => {},
                BlockDecodingStrategy::UptoBlocks(n) => {
                    if self.state.block_counter - block_counter_before >= n {
                        break Result::Ok(());
                    }
                },
                BlockDecodingStrategy::UptoBytes(n) => {
                    if self.state.decoder_scratch.buffer.len() - buffer_size_before >= n {
                        break Result::Ok(());
                    }
                },
            }
        };

        if result.is_err() {
            return Result::Err(result.unwrap_err());
        }

        Result::Ok(self.state.frame_finished)
    }

    fn collect(ref self: FrameDecoder) -> Option<ByteArray> {
        let finished = self.is_finished();
        if finished {
            Option::Some(self.state.decoder_scratch.buffer.drain())
        } else {
            self.state.decoder_scratch.buffer.drain_to_window_size()
        }
    }

    fn can_collect(self: @FrameDecoder) -> usize {
        let finished = self.is_finished();
        if finished {
            self.state.decoder_scratch.buffer.can_drain()
        } else {
            match self.state.decoder_scratch.buffer.can_drain_to_window_size() {
                Option::Some(val) => val,
                Option::None => 0,
            }
        }
    }

    fn decode_from_to(
        ref self: FrameDecoder, source: @ByteArraySlice, ref target: ByteArray,
    ) -> Result<(usize, usize), FrameDecoderError> {
        let bytes_read_at_start = self.state.bytes_read_counter;

        if !self.is_finished() {
            let mut mt_source = source;

            let mut block_dec = BlockDecoderTrait::new();

            if self.state.frame.header.descriptor.content_checksum_flag()
                && self.state.frame_finished
                && self.state.check_sum.is_none() {
                if mt_source.len() >= 4 {
                    let checksum = mt_source.slice(0, 4);
                    mt_source = @mt_source.slice(4, mt_source.len());
                    self.state.bytes_read_counter += 4;

                    let checksum = checksum.word_u32_le(0).unwrap();
                    self.state.check_sum = Option::Some(checksum);
                }
                return Result::Ok((4, 0));
            }

            let result = loop {
                if mt_source.len() < 3 {
                    break Result::Ok(());
                }

                let (block_header, block_header_size) =
                    match block_dec.read_block_header(ref mt_source) {
                    Result::Ok(val) => val,
                    Result::Err(err) => {
                        break Result::Err(FrameDecoderError::FailedToReadBlockHeader(err));
                    },
                };

                if mt_source.len() < block_header.content_size.into() {
                    break Result::Ok(());
                }
                self.state.bytes_read_counter += block_header_size.into();

                let bytes_read_in_block_body =
                    match block_dec
                        .decode_block_content(
                            @block_header, ref self.state.decoder_scratch, ref mt_source,
                        ) {
                    Result::Ok(val) => val,
                    Result::Err(err) => {
                        break Result::Err(FrameDecoderError::FailedToReadBlockBody(err));
                    },
                };
                self.state.bytes_read_counter += bytes_read_in_block_body;
                self.state.block_counter += 1;

                if block_header.last_block {
                    self.state.frame_finished = true;
                    if self.state.frame.header.descriptor.content_checksum_flag() {
                        if mt_source.len() >= 4 {
                            let checksum = mt_source.slice(0, 4);
                            mt_source = @mt_source.slice(4, mt_source.len());
                            self.state.bytes_read_counter += 4;

                            let checksum = checksum.word_u32_le(0).unwrap();
                            self.state.check_sum = Option::Some(checksum);
                        }
                    }
                    break Result::Ok(());
                }
            };

            if result.is_err() {
                return Result::Err(result.unwrap_err());
            }
        }

        let result_len = self.read(ref target);
        let bytes_read_at_end = self.state.bytes_read_counter;
        let read_len = bytes_read_at_end - bytes_read_at_start;

        Result::Ok((read_len.try_into().unwrap(), result_len))
    }

    fn read(ref self: FrameDecoder, ref target: ByteArray) -> usize {
        if self.state.frame_finished {
            self.state.decoder_scratch.buffer.read_all(ref target)
        } else {
            self.state.decoder_scratch.buffer.read(ref target)
        }
    }
}
