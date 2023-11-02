use integer::BoundedInt;

impl I32TryIntoU32 of TryInto<i32, u32> {
    fn try_into(self: i32) -> Option<u32> {
        if self < 0 {
            return Option::None;
        }

        let val_felt: felt252 = self.into();

        Option::Some(val_felt.try_into()?)
    }
}

impl I32TryIntoU64 of TryInto<i32, u64> {
    fn try_into(self: i32) -> Option<u64> {
        if self < 0 {
            return Option::None;
        }

        let val_felt: felt252 = self.into();

        Option::Some(val_felt.try_into()?)
    }
}

impl U32TryIntoI32 of TryInto<u32, i32> {
    fn try_into(self: u32) -> Option<i32> {
        let u32_max: u32 = BoundedInt::max();

        if self > u32_max / 2 - 1 {
            return Option::None;
        }

        let val_felt: felt252 = self.into();

        Option::Some(val_felt.try_into()?)
    }
}

impl I64TryIntoU64 of TryInto<i64, u64> {
    fn try_into(self: i64) -> Option<u64> {
        if self < 0 {
            return Option::None;
        }

        let val_felt: felt252 = self.into();

        Option::Some(val_felt.try_into()?)
    }
}

impl U64TryIntoI64 of TryInto<u64, i64> {
    fn try_into(self: u64) -> Option<i64> {
        let u64_max: u64 = BoundedInt::max();

        if self > u64_max / 2 - 1 {
            return Option::None;
        }

        let val_felt: felt252 = self.into();

        Option::Some(val_felt.try_into()?)
    }
}

impl I64TryIntoI32 of TryInto<i64, i32> {
    fn try_into(self: i64) -> Option<i32> {
        let val_felt: felt252 = self.into();

        Option::Some(val_felt.try_into()?)
    }
}

impl I32TryIntoU8 of TryInto<i32, u8> {
    fn try_into(self: i32) -> Option<u8> {
        let u8_max: u32 = BoundedInt::max();

        if self < 0 {
            return Option::None;
        }

        let val_felt: felt252 = self.into();

        Option::Some(val_felt.try_into()?)
    }
}

impl U8TryIntoI32 of Into<u8, i32> {
    fn into(self: u8) -> i32 {
        let val_felt: felt252 = self.into();

        val_felt.try_into().unwrap()
    }
}

impl I32Div of Div<i32> {
    fn div(lhs: i32, rhs: i32) -> i32 {
        if rhs == 0 {
            panic_with_felt252('Division by 0');
        }

        i32_div(lhs, rhs)
    }
}

fn i32_div(mut lhs: i32, mut rhs: i32) -> i32 {
    let mut flip = true;

    if lhs < 0 && rhs > 0 {
        lhs *= -1;
    } else if lhs > 0 && rhs < 0 {
        rhs *= -1;
    } else {
        flip = false;
    }

    let lhs_u32: u32 = lhs.try_into().unwrap();
    let result_u32: u32 = lhs_u32 / rhs.try_into().unwrap();
    let mut result: i32 = result_u32.try_into().unwrap();

    if flip {
        result *= -1;
    }

    result
}

trait Bits<T> {
    #[inline(always)]
    fn BITS() -> usize;
}

impl U8Bits of Bits<u8> {
    #[inline(always)]
    fn BITS() -> usize {
        8
    }
}

impl U16Bits of Bits<u16> {
    #[inline(always)]
    fn BITS() -> usize {
        16
    }
}

impl U32Bits of Bits<u32> {
    #[inline(always)]
    fn BITS() -> usize {
        32
    }
}

impl U64Bits of Bits<u64> {
    #[inline(always)]
    fn BITS() -> usize {
        64
    }
}

impl U128Bits of Bits<u128> {
    #[inline(always)]
    fn BITS() -> usize {
        128
    }
}

impl U256Bits of Bits<u256> {
    #[inline(always)]
    fn BITS() -> usize {
        256
    }
}

