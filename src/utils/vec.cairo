use alexandria_data_structures::vec::{VecTrait, Felt252Vec, NullableVec};

trait Concat<V, T> {
    fn concat(ref self: V, ref other: V);
}

impl Felt252VecConcatImpl<
    T, +VecTrait<Felt252Vec<T>, T>, +Destruct<Felt252Dict<T>>, +Destruct<Felt252Vec<T>>
> of Concat<Felt252Vec<T>, T> {
    fn concat(ref self: Felt252Vec<T>, ref other: Felt252Vec<T>) {
        let mut i: usize = 0;
        let other_len = other.len();

        loop {
            if i >= other_len {
                break;
            }

            self.push(other.at(i));

            i += 1;
        };
    }
}

impl NullableVecConcatImpl<
    T, +VecTrait<NullableVec<T>, T>, +Destruct<Felt252Dict<Nullable<T>>>, +Destruct<NullableVec<T>>
> of Concat<NullableVec<T>, T> {
    fn concat(ref self: NullableVec<T>, ref other: NullableVec<T>) {
        let mut i: usize = 0;
        let other_len = other.len();

        loop {
            if i >= other_len {
                break;
            }

            self.push(other.at(i));

            i += 1;
        };
    }
}

trait Resize<V, T> {
    fn resize(ref self: V, new_len: usize, value: T);
}

impl Felt252VecResize<
    T,
    +VecTrait<Felt252Vec<T>, T>,
    +Destruct<Felt252Dict<T>>,
    +Destruct<Felt252Vec<T>>,
    +Drop<T>,
    +Copy<T>
> of Resize<Felt252Vec<T>, T> {
    fn resize(ref self: Felt252Vec<T>, new_len: usize, value: T) {
        let mut len = self.len;

        if new_len > len {
            loop {
                if len >= new_len {
                    break;
                }

                self.push(value);

                len += 1;
            };
        } else if new_len < len {
            self.len = new_len;
        }
    }
}

impl NullableVecResize<T, +Drop<T>, +Copy<T>> of Resize<NullableVec<T>, T> {
    fn resize(ref self: NullableVec<T>, new_len: usize, value: T) {
        let mut len = self.len;

        if new_len > len {
            loop {
                if len >= new_len {
                    break;
                }

                self.push(value);

                len += 1;
            };
        } else if new_len < len {
            self.len = new_len;
        }
    }
}

trait Clear<V> {
    fn clear(ref self: V);
}

impl Felt252VecClear<
    T, +Felt252DictValue<T>, +Destruct<Felt252Dict<T>>, +Destruct<Felt252Vec<T>>
> of Clear<Felt252Vec<T>> {
    fn clear(ref self: Felt252Vec<T>) {
        self.items = Default::default();
        self.len = 0;
    }
}

impl NullableVecClear<
    T, +Destruct<Felt252Dict<Nullable<T>>>, +Destruct<NullableVec<T>>
> of Clear<NullableVec<T>> {
    fn clear(ref self: NullableVec<T>) {
        self.items = Default::default();
        self.len = 0;
    }
}

trait Reserve<V> {
    fn reserve(ref self: V, size: usize);
}

impl Felt252VecReserve<T, +Felt252DictValue<T>> of Reserve<Felt252Vec<T>> {
    fn reserve(ref self: Felt252Vec<T>, size: usize) { // no-op
    }
}

impl NullableVecReserve<T> of Reserve<NullableVec<T>> {
    fn reserve(ref self: NullableVec<T>, size: usize) { // no-op
    }
}

impl SpanIntoVec<
    T, V, impl VecTraitImpl: VecTrait<V, T>, +Destruct<V>, +Copy<T>
> of Into<Span<T>, V> {
    fn into(self: Span<T>) -> V {
        let mut i: usize = 0;
        let len = self.len();
        let mut vec = VecTrait::<V, T>::new();

        loop {
            if i >= len {
                break;
            }

            vec.push(*self.at(i));

            i += 1;
        };

        vec
    }
}
