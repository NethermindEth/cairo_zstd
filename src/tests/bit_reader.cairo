use byte_array::ByteArray;
use debug::PrintTrait;

use alexandria_math::BitShift;

use cairo_zstd::decoding::bit_reader::{BitReaderTrait};
use cairo_zstd::decoding::bit_reader_reverse::{BitReaderReversedTrait};

#[test]
#[available_gas(2000000000)]
fn test_bitreader_reversed() {
    let mut ba: ByteArray = Default::default();
    ba.append_word(0xC141080000ECC8964279D4BCF72CD548, 16);

    let num_rev: u128 = 0x48_D5_2C_F7_BC_D4_79_42_96_C8_EC_00_00_08_41_C1;

    let mut br = BitReaderReversedTrait::new(@ba);
    let mut accumulator: u128 = 0;
    let mut bits_read = 0;
    let mut x: u8 = 0;

    loop {
        x += 3;

        let mut num_bits = x % 16;
        if bits_read > 128 - num_bits {
            num_bits = 128 - bits_read;
        }

        let bits: u128 = br.get_bits(num_bits).unwrap().into();

        bits_read += num_bits;
        accumulator = accumulator | BitShift::shl(bits, 128 - bits_read.into());

        if bits_read >= 128 {
            break;
        }
    };

    if accumulator != num_rev {
        'Bitreader failed somewhere.'.print();
        'Accumulated bits: '.print();
        accumulator.print();
        'Should be'.print();
        num_rev.print();

        panic_with_felt252('Error!');
    }
}

#[test]
#[available_gas(20000000)]
fn test_bitreader_normal() {
    let mut ba: ByteArray = Default::default();
    ba.append_word(0xC141080000ECC8964279D4BCF72CD548, 16);

    let num: u128 = 0x48_D5_2C_F7_BC_D4_79_42_96_C8_EC_00_00_08_41_C1;

    let mut br = BitReaderTrait::new(@ba);
    let mut accumulator: u128 = 0;
    let mut bits_read = 0;
    let mut x = 0;

    loop {
        x += 3;

        let mut num_bits = x % 16;
        if bits_read > 128 - num_bits {
            num_bits = 128 - bits_read;
        }

        let bits: u128 = br.get_bits(num_bits).unwrap().into();

        accumulator = accumulator | BitShift::shl(bits, bits_read.into());
        bits_read += num_bits;

        if bits_read >= 128 {
            break;
        }
    };

    if accumulator != num {
        'Bitreader failed somewhere.'.print();
        'Accumulated bits: '.print();
        accumulator.print();
        'Should be'.print();
        num.print();

        panic_with_felt252('Error!');
    }
}
