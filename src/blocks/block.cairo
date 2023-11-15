#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BlockType {
    Raw,
    RLE,
    Compressed,
    Reserved,
}

struct BlockHeader {
    last_block: bool,
    block_type: BlockType,
    decompressed_size: u32,
    content_size: u32,
}
