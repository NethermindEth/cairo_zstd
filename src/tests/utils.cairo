use cairo_zstd::utils::math::{Bits, LeadingZeros, HighestBitSet, IsPowerOfTwo};

#[test]
fn test_bits() {
    assert(Bits::<u8>::BITS() == 8, 'Wrong bit count');
    assert(Bits::<u16>::BITS() == 16, 'Wrong bit count');
    assert(Bits::<u32>::BITS() == 32, 'Wrong bit count');
    assert(Bits::<u64>::BITS() == 64, 'Wrong bit count');
    assert(Bits::<u128>::BITS() == 128, 'Wrong bit count');
    assert(Bits::<u256>::BITS() == 256, 'Wrong bit count');
}

#[test]
#[available_gas(2000000000)]
fn test_leading_zeros() {
    _test_leading_zeros::<u8>();
    _test_leading_zeros::<u16>();
    _test_leading_zeros::<u32>();
    _test_leading_zeros::<u64>();
    _test_leading_zeros::<u128>();
    _test_leading_zeros::<u256>();
}

fn _test_leading_zeros<
    T, +LeadingZeros<T>, +Bits<T>, +Into<u8, T>, +MulEq<T>, +Copy<T>, +Drop<T>
>() {
    let mut value: T = 0_u8.into();
    let mut expected_leading_zeros = Bits::<T>::BITS();

    assert(value.leading_zeros() == expected_leading_zeros, 'Wrong leading zeros count');

    value = 1_u8.into();
    expected_leading_zeros -= 1;
    assert(value.leading_zeros() == expected_leading_zeros, 'Wrong leading zeros count');

    loop {
        if expected_leading_zeros == 0 {
            break;
        }

        value *= 2_u8.into();
        expected_leading_zeros -= 1;

        assert(value.leading_zeros() == expected_leading_zeros, 'Wrong leading zeros count');
    };
}

#[test]
#[available_gas(2000000000)]
fn test_highest_bit_set() {
    _test_highest_bit_set::<u8>();
    _test_highest_bit_set::<u16>();
    _test_highest_bit_set::<u32>();
    _test_highest_bit_set::<u64>();
    _test_highest_bit_set::<u128>();
    _test_highest_bit_set::<u256>();
}

fn _test_highest_bit_set<
    T,
    +HighestBitSet<T>,
    +Bits<T>,
    +Into<u8, T>,
    +TryInto<T, NonZero<T>>,
    +MulEq<T>,
    +Copy<T>,
    +Drop<T>
>() {
    let mut value: T = 1_u8.into();
    let mut expected_highest_bit_set = 1;

    let non_zero_value: NonZero<T> = value.try_into().unwrap();
    assert(non_zero_value.highest_bit_set() == expected_highest_bit_set, 'Wrong highest bit set');

    loop {
        if expected_highest_bit_set == Bits::<T>::BITS() {
            break;
        }

        value *= 2_u8.into();
        expected_highest_bit_set += 1;

        let non_zero_value: NonZero<T> = value.try_into().unwrap();
        assert(
            non_zero_value.highest_bit_set() == expected_highest_bit_set, 'Wrong highest bit set'
        );
    };
}

#[test]
#[available_gas(2000000000)]
fn test_is_power_of_two() {
    _test_is_power_of_two::<u8>();
    _test_is_power_of_two::<u16>();
    _test_is_power_of_two::<u32>();
    _test_is_power_of_two::<u64>();
    _test_is_power_of_two::<u128>();
    _test_is_power_of_two::<u256>();
}

fn _test_is_power_of_two<
    T, +IsPowerOfTwo<T>, +Bits<T>, +Into<u8, T>, +Add<T>, +Sub<T>, +MulEq<T>, +Copy<T>, +Drop<T>
>() {
    let mut value: T = 0_u8.into();
    assert(!value.is_power_of_two(), 'Wrong power of two check');

    value = 1_u8.into();
    assert(value.is_power_of_two(), 'Wrong power of two check');

    value = 2_u8.into();
    assert(value.is_power_of_two(), 'Wrong power of two check');

    let mut i: usize = 2;
    loop {
        if i == Bits::<T>::BITS() {
            break;
        }

        value *= 2_u8.into();
        assert(value.is_power_of_two(), 'Wrong power of two check');
        assert(!(value + 1_u8.into()).is_power_of_two(), 'Wrong power of two check');
        assert(!(value - 1_u8.into()).is_power_of_two(), 'Wrong power of two check');

        i += 1;
    };
}
