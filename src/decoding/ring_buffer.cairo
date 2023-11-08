use byte_array::{ByteArray, ByteArrayTrait};
use cmp::min;

use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait};

// Only a byte array wrapper for now

#[derive(Drop)]
struct RingBuffer {
    elements: ByteArray,
    head: usize,
    tail: usize,
}

#[generate_trait]
impl RingBufferImpl of RingBufferTrait {
    fn new() -> RingBuffer {
        RingBuffer { elements: Default::default(), head: 0, tail: 0, }
    }

    fn len(self: @RingBuffer) -> usize {
        self.elements.len()
    }

    #[inline(always)]
    fn clear(ref self: RingBuffer) { // no-op
    }

    fn is_empty(self: @RingBuffer) -> bool {
        self.elements.len() == 0
    }

    #[inline(always)]
    fn reserve(ref self: RingBuffer, amount: usize) { // no-op
    }

    fn push_back(ref self: RingBuffer, byte: u8) {
        self.elements.append_byte(byte);
        self.tail += 1;
    }

    fn get(self: @RingBuffer, idx: usize) -> Option<u8> {
        self.elements.at(idx)
    }

    fn extend(ref self: RingBuffer, data: @ByteArray) {
        self.elements.append(data);
        self.tail += data.len()
    }

    fn drop_first_n(ref self: RingBuffer, amount: usize) {
        assert(amount <= self.len(), 'Not enough elements');

        let amount = min(amount, self.len());
        self.head += amount;
    }

    fn as_slice(self: @RingBuffer) -> ByteArraySlice {
        ByteArraySliceTrait::new(self.elements, *self.head, *self.tail)
    }
}
