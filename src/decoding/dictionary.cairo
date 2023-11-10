use byte_array::ByteArray;

use alexandria_data_structures::byte_array_ext::ByteArrayTraitExt;

use cairo_zstd::decoding::scratch::{FSEScratch, FSEScratchTrait};
use cairo_zstd::decoding::scratch::{HuffmanScratch, HuffmanScratchTrait};
use cairo_zstd::fse::fse_decoder::{FSETableTrait, FSETableError};
use cairo_zstd::huff0::huff0_decoder::{HuffmanTableTrait, HuffmanTableError};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait, ByteArrayTraitExtRead};

#[derive(Drop)]
struct Dictionary {
    id: u32,
    fse: FSEScratch,
    huf: HuffmanScratch,
    dict_content: ByteArraySlice,
    offset_hist: (u32, u32, u32),
}

#[derive(Drop)]
enum DictionaryDecodeError {
    BadMagicNum: (u32,),
    FSETableError: FSETableError,
    HuffmanTableError: HuffmanTableError,
}

const LL_MAX_LOG: u8 = 9;
const ML_MAX_LOG: u8 = 9;
const OF_MAX_LOG: u8 = 8;

const MAGIC_NUM: u32 = 0xEC30A437;

#[generate_trait]
impl DictionaryImpl of DictionaryTrait {
    fn decode_dict(raw: @ByteArray) -> Result<Dictionary, DictionaryDecodeError> {
        let mut new_dict = Dictionary {
            id: 0,
            fse: FSEScratchTrait::new(),
            huf: HuffmanScratchTrait::new(),
            dict_content: Default::default(),
            offset_hist: (2, 4, 8),
        };

        let magic_num = raw.word_u32_le(0).expect('optimized away');
        if magic_num != MAGIC_NUM {
            return Result::Err(DictionaryDecodeError::BadMagicNum((magic_num,)));
        }

        let dict_id = raw.word_u32_le(4).expect('optimized away');
        new_dict.id = dict_id;

        let raw_tables = ByteArraySliceTrait::new(raw, 8, raw.len());

        let huf_size = match new_dict.huf.table.build_decoder(raw_tables) {
            Result::Ok(val) => val,
            Result::Err(err) => {
                return Result::Err(DictionaryDecodeError::HuffmanTableError(err));
            },
        };
        let raw_tables = raw_tables.slice(huf_size, raw_tables.len());

        let of_size = match new_dict.fse.offsets.build_decoder(raw_tables, OF_MAX_LOG,) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(DictionaryDecodeError::FSETableError(err)); },
        };
        let raw_tables = raw_tables.slice(of_size, raw_tables.len());

        let ml_size = match new_dict.fse.match_lengths.build_decoder(raw_tables, ML_MAX_LOG,) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(DictionaryDecodeError::FSETableError(err)); },
        };
        let raw_tables = raw_tables.slice(ml_size, raw_tables.len());

        let ll_size = match new_dict.fse.literal_lengths.build_decoder(raw_tables, LL_MAX_LOG,) {
            Result::Ok(val) => val,
            Result::Err(err) => { return Result::Err(DictionaryDecodeError::FSETableError(err)); },
        };
        let raw_tables = raw_tables.slice(ll_size, raw_tables.len());

        let offset1 = raw_tables.word_u32_le(0).expect('optimized away');
        let offset2 = raw_tables.word_u32_le(4).expect('optimized away');
        let offset3 = raw_tables.word_u32_le(8).expect('optimized away');

        new_dict.offset_hist = (offset1, offset2, offset3);

        let raw_content = raw_tables.slice(12, raw_tables.len());
        new_dict.dict_content = raw_content;

        Result::Ok(new_dict)
    }
}
