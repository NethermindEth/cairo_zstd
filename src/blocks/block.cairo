#[derive(Copy, Debug, Clone, Drop, PartialEq, Eq)]
enum BlockType {
    Raw,
    RLE,
    Compressed,
    Reserved,
}

// impl BlockTypeDisplayImpl of Display<BlockType>{
//     fn fmt(self: @BlockType, ref f: Formatter) -> Result<(), Error> {
//         match self {
//             BlockType::Raw => f.buffer.append("Raw").print();
//             BlockType::RLE => f.buffer.append("RLE"),
//             BlockType::Compressed => f.buffer.append("Compressed"),
//             BlockType::Reserved => f.buffer.append("Reserved"),
//         }
//         Result::Ok(());
//     }
// }

#[derive(Copy, Drop)]
struct BlockHeader {
    last_block: bool,
    block_type: BlockType,
    decompressed_size: u32,
    content_size: u32
}
