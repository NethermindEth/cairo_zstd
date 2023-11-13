use array::{Array, ArrayTrait};

use cairo_zstd::decoding::decode_buffer::{DecodeBuffer, DecodeBufferTrait};
use cairo_zstd::decoding::dictionary::{Dictionary, DictionaryTrait};
use cairo_zstd::fse::fse_decoder::{FSETable, FSETableTrait};
use cairo_zstd::huff0::huff0_decoder::{HuffmanTable, HuffmanTableTrait};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};

#[derive(Clone, Copy, Drop)]
struct Sequence {
    literals_length: u32,
    match_length: u32,
    offset: u32,
}

#[derive(Drop)]
struct DecoderScratch {
    huf: HuffmanScratch,
    fse: FSEScratch,
    buffer: DecodeBuffer,
    offset_hist: (u32, u32, u32),
    literals_buffer: ByteArraySlice,
    sequences: Array<Sequence>,
    block_content_buffer: ByteArraySlice,
}

#[generate_trait]
impl DecoderScratchImpl of DecoderScratchTrait {
    fn new(window_size: usize) -> DecoderScratch {
        DecoderScratch {
            huf: HuffmanScratch { table: HuffmanTableTrait::new(), },
            fse: FSEScratch {
                offsets: FSETableTrait::new(),
                of_rle: Option::None,
                literal_lengths: FSETableTrait::new(),
                ll_rle: Option::None,
                match_lengths: FSETableTrait::new(),
                ml_rle: Option::None,
            },
            buffer: DecodeBufferTrait::new(window_size),
            offset_hist: (1, 4, 8),
            block_content_buffer: Default::default(),
            literals_buffer: Default::default(),
            sequences: ArrayTrait::new(),
        }
    }

    fn reset(ref self: DecoderScratch, window_size: usize) {
        self.offset_hist = (1, 4, 8);
        self.literals_buffer = Default::default();
        self.sequences = ArrayTrait::new();
        self.block_content_buffer = Default::default();

        self.buffer.reset(window_size);

        self.fse.literal_lengths.reset();
        self.fse.match_lengths.reset();
        self.fse.offsets.reset();
        self.fse.ll_rle = Option::None;
        self.fse.ml_rle = Option::None;
        self.fse.of_rle = Option::None;

        self.huf.table.reset();
    }

    fn init_from_dict(ref self: DecoderScratch, ref dict: Dictionary) {
        self.fse.reinit_from(ref dict.fse);
        self.huf.table.reinit_from(ref dict.huf.table);
        self.offset_hist = dict.offset_hist;
        self.buffer.dict_content = dict.dict_content;
    }
}

#[derive(Drop)]
struct HuffmanScratch {
    table: HuffmanTable,
}

#[generate_trait]
impl HuffmanScratchImpl of HuffmanScratchTrait {
    fn new() -> HuffmanScratch {
        HuffmanScratch { table: HuffmanTableTrait::new(), }
    }
}

impl HuffmanScratchDefault of Default<HuffmanScratch> {
    fn default() -> HuffmanScratch {
        HuffmanScratchTrait::new()
    }
}

#[derive(Drop)]
struct FSEScratch {
    offsets: FSETable,
    of_rle: Option<u8>,
    literal_lengths: FSETable,
    ll_rle: Option<u8>,
    match_lengths: FSETable,
    ml_rle: Option<u8>,
}

#[generate_trait]
impl FSEScratchImpl of FSEScratchTrait {
    fn new() -> FSEScratch {
        FSEScratch {
            offsets: FSETableTrait::new(),
            of_rle: Option::None,
            literal_lengths: FSETableTrait::new(),
            ll_rle: Option::None,
            match_lengths: FSETableTrait::new(),
            ml_rle: Option::None,
        }
    }

    fn reinit_from(ref self: FSEScratch, ref other: FSEScratch) {
        self.offsets.reinit_from(ref other.offsets);
        self.literal_lengths.reinit_from(ref other.literal_lengths);
        self.match_lengths.reinit_from(ref other.match_lengths);
        self.of_rle = other.of_rle;
        self.ll_rle = other.ll_rle;
        self.ml_rle = other.ml_rle;
    }
}

impl FSEScratchDefault of Default<FSEScratch> {
    fn default() -> FSEScratch {
        FSEScratchTrait::new()
    }
}
