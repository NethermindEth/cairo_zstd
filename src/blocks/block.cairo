// #[derive(Drop)]
// struct Error {}

// #[derive(Default, Drop)]
// struct Formatter {
//     /// The pending result of formatting.
//     buffer: ByteArray,
// }

// trait Display<T> {
//     fn fmt(self: @T, ref f: Formatter) -> Result<(), Error>;
// }

#[derive(Copy, Clone, Drop, PartialEq)]
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
