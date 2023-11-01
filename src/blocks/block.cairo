use debug::PrintTrait;
use core::corelib::src::fmt::Display;
#[derive(Drop)]
enum BlockType {
    Raw,
    RLE,
    Compressed,
    Reserved
}

impl BlockTypeImpl of Display<BlockType> {
    fn fmt(self: @BlockType, ref f: BlockType) -> Result<(), Error> {
        match self {
            BlockType::Raw => 'Raw'.print(),
            BlockType::RLE => 'RLE'.print(),
            BlockType::Compressed =>'Compressed'.print(),
            BlockType::Reserved =>'Reserved'.print(),
        }
    }
}


#[derive(Copy, Drop)]
struct BlockHeader {
    last_block: bool,
    block_type: BlockType,
    decompressed_size: u32,
    content_size: u32
}