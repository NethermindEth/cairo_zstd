mod z000001;

use cairo_zstd::frame_decoder::{FrameDecoderTrait, FrameDecoderStateTrait, BlockDecodingStrategy};
use cairo_zstd::utils::byte_array::ByteArraySliceTrait;

fn _test_decode(source: @ByteArray, expected_result: @ByteArray) {
    let mut source = @ByteArraySliceTrait::new(source, 0, source.len());

    let state = FrameDecoderStateTrait::new(ref source).unwrap();

    let mut frame_decoder = FrameDecoderTrait::new(state);
    frame_decoder.decode_blocks(ref source, BlockDecodingStrategy::All);

    assert(frame_decoder.is_finished(), 'not finished');

    let result = frame_decoder.collect().unwrap();

    assert(
        frame_decoder.get_checksum_from_data() == frame_decoder.get_calculated_checksum(),
        'checksums do not match'
    );
    assert(@result == expected_result, 'wrong decoding result');
}

#[test]
#[available_gas(200000000000)]
fn test_decode_z000001() {
    _test_decode(@z000001::get_compressed(), @z000001::get_data());
}
