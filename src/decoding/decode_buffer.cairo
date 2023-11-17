use cmp::min;
use byte_array::{ByteArray, ByteArrayTrait};

use cairo_zstd::decoding::ring_buffer::{RingBuffer, RingBufferTrait};
use cairo_zstd::utils::xxhash64::{XxHash64, XxHash64Trait};
use cairo_zstd::utils::byte_array::{ByteArraySlice, ByteArraySliceTrait, ByteArrayExtendSliceImpl};

#[derive(Drop)]
struct DecodeBuffer {
    buffer: RingBuffer,
    dict_content: ByteArraySlice,
    window_size: usize,
    total_output_counter: u64,
    hash: XxHash64,
}

#[derive(Copy, Drop)]
enum DecodeBufferError {
    NotEnoughBytesInDictionary: (usize, usize),
    OffsetTooBig: (usize, usize),
}

#[generate_trait]
impl DecodeBufferImpl of DecodeBufferTrait {
    fn new(window_size: usize) -> DecodeBuffer {
        DecodeBuffer {
            buffer: RingBufferTrait::new(),
            dict_content: Default::default(),
            window_size,
            total_output_counter: 0,
            hash: XxHash64Trait::new(0),
        }
    }

    fn reset(ref self: DecodeBuffer, window_size: usize) {
        self.window_size = window_size;
        self.buffer.clear();
        self.buffer.reserve(self.window_size);
        self.dict_content = Default::default();
        self.total_output_counter = 0;
        self.hash = XxHash64Trait::new(0);
    }

    fn len(self: @DecodeBuffer) -> usize {
        self.buffer.len()
    }

    fn is_empty(self: @DecodeBuffer) -> bool {
        self.buffer.is_empty()
    }

    fn append_byte(ref self: DecodeBuffer, byte: u8) {
        self.buffer.push_back(byte);
        self.total_output_counter += 1;
    }

    fn push(ref self: DecodeBuffer, data: @ByteArraySlice) {
        self.buffer.extend_slice(data);
        self.total_output_counter += data.len().into();
    }

    fn repeat(
        ref self: DecodeBuffer, offset: usize, match_length: usize
    ) -> Result<(), DecodeBufferError> {
        if offset > self.buffer.len() {
            if self.total_output_counter <= self.window_size.into() {
                let bytes_from_dict = offset - self.buffer.len();

                if bytes_from_dict > self.dict_content.len() {
                    return Result::Err(
                        DecodeBufferError::NotEnoughBytesInDictionary(
                            (self.dict_content.len(), bytes_from_dict)
                        )
                    );
                }

                if bytes_from_dict < match_length {
                    let dict_slice = @self
                        .dict_content
                        .slice(self.dict_content.len() - bytes_from_dict, self.dict_content.len());
                    self.buffer.extend_slice(dict_slice);

                    self.total_output_counter += bytes_from_dict.into();
                    return self.repeat(self.buffer.len(), match_length - bytes_from_dict);
                } else {
                    let low = self.dict_content.len() - bytes_from_dict;
                    let high = low + match_length;
                    let dict_slice = @self.dict_content.slice(low, high);
                    self.buffer.extend_slice(dict_slice);
                }
            } else {
                return Result::Err(DecodeBufferError::OffsetTooBig((offset, self.buffer.len())));
            }
        } else {
            let buf_len = self.buffer.len();
            let start_idx = buf_len - offset;
            let end_idx = start_idx + match_length;

            self.buffer.reserve(match_length);

            if end_idx > buf_len {
                let mut start_idx = start_idx;
                let mut copied_counter_left = match_length;
                loop {
                    if !(copied_counter_left > 0) {
                        break;
                    }

                    let chunksize = min(offset, copied_counter_left);

                    self
                        .buffer
                        .extend_slice(
                            @ByteArraySliceTrait::new(
                                @self.buffer.elements, start_idx, start_idx + chunksize
                            )
                        );
                    copied_counter_left -= chunksize;
                    start_idx += chunksize;
                };
            } else {
                self
                    .buffer
                    .extend_slice(
                        @ByteArraySliceTrait::new(@self.buffer.elements, start_idx, end_idx)
                    );
            }

            self.total_output_counter += match_length.into();
        }

        Result::Ok(())
    }

    fn can_drain_to_window_size(self: @DecodeBuffer) -> Option<usize> {
        if self.buffer.len() > *self.window_size {
            Option::Some(self.buffer.len() - *self.window_size)
        } else {
            Option::None
        }
    }

    fn can_drain(self: @DecodeBuffer) -> usize {
        self.buffer.len()
    }

    fn drain_to_window_size(ref self: DecodeBuffer) -> Option<ByteArray> {
        match self.can_drain_to_window_size() {
            Option::Some(can_drain) => {
                let mut ba = self.drain_to(can_drain);
                Option::Some(ba)
            },
            Option::None => Option::None,
        }
    }

    fn drain(ref self: DecodeBuffer) -> ByteArray {
        let slice = @self.buffer.as_slice();
        let mut ba: ByteArray = Default::default(); // improve this
        ba.extend_slice(slice);

        self.hash.update(@ba);

        self.buffer.clear();
        ba
    }

    fn drain_to(ref self: DecodeBuffer, amount: usize) -> ByteArray {
        let mut ba: ByteArray = Default::default();

        if amount == 0 {
            return ba;
        }

        let slice = self.buffer.as_slice();
        let n = min(slice.len(), amount);

        let subslice = @slice.slice(0, n);

        ba.extend_slice(subslice);
        self.hash.update(@ba);

        self.buffer.drop_first_n(n);

        ba
    }

    fn read(ref self: DecodeBuffer, ref target: ByteArray) -> usize {
        let amount = match self.can_drain_to_window_size() {
            Option::Some(val) => val,
            Option::None => 0,
        };

        target.append(@self.drain_to(amount));
        amount
    }

    fn read_all(ref self: DecodeBuffer, ref target: ByteArray) -> usize {
        let amount = self.buffer.len();

        target.append(@self.drain_to(amount));
        amount
    }
}

