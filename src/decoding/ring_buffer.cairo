use byte_array::{ByteArray, ByteArrayTrait};
use cmp::min;

use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait, ByteArrayExtendSliceImpl};

// Only a byte array wrapper for now

#[derive(Drop)]
struct RingBuffer {
    elements: ByteArray,
    head: usize,
}

#[generate_trait]
impl RingBufferImpl of RingBufferTrait {
    fn new() -> RingBuffer {
        RingBuffer { elements: Default::default(), head: 0 }
    }

    fn len(self: @RingBuffer) -> usize {
        self.elements.len()
    }

    #[inline(always)]
    fn clear(ref self: RingBuffer) {
        self.elements = Default::default();
        self.head = 0;
    }

    fn is_empty(self: @RingBuffer) -> bool {
        self.elements.len() == 0
    }

    #[inline(always)]
    fn reserve(ref self: RingBuffer, amount: usize) { // no-op
    }

    fn push_back(ref self: RingBuffer, byte: u8) {
        self.elements.append_byte(byte);
    }

    fn get(self: @RingBuffer, idx: usize) -> Option<u8> {
        self.elements.at(*self.head + idx)
    }

    fn extend(ref self: RingBuffer, data: @ByteArray) {
        self.elements.append(data);
    }

    fn extend_slice(ref self: RingBuffer, data: ByteArraySlice) {
        self.elements.extend_slice(data);
    }

    fn drop_first_n(ref self: RingBuffer, amount: usize) {
        assert(amount <= self.len(), 'Not enough elements');

        let amount = min(amount, self.len());
        self.head += amount;
    }

    fn as_slice(self: @RingBuffer) -> ByteArraySlice {
        ByteArraySliceTrait::new(self.elements, *self.head, self.elements.len())
    }
}
