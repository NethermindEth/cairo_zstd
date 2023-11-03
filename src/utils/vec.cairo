use alexandria_data_structures::vec::{VecTrait, Felt252Vec};

trait Concat<V, T> {
    fn concat(ref self: V, ref other: V);
}

impl ConcatImpl<V, T, impl VecTraitImpl: VecTrait<V, T>, +Drop<V>> of Concat<V, T> {
    fn concat(ref self: V, ref other: V) {
        let mut i: usize = 0;
        let other_len = other.len();

        loop {
            if i == other_len {
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
    T, +Felt252DictValue<T>, +Drop<Felt252Dict<T>>, +Drop<Felt252Vec<T>>, +Copy<T>, +Drop<T>
> of Resize<Felt252Vec<T>, T> {
    fn resize(ref self: Felt252Vec<T>, new_len: usize, value: T) {
        let mut len = self.len;

        if new_len > len {
            loop {
                if len == new_len {
                    break;
                }

                self.push(value);

                len += 1;
            }
        } else if new_len < len {
            self.len = new_len;
        }
    }
}

trait Clear<V> {
    fn clear(ref self: V);
}

impl Felt252VecClear<
    T, +Felt252DictValue<T>, +Drop<Felt252Dict<T>>, +Drop<Felt252Vec<T>>
> of Clear<Felt252Vec<T>> {
    fn clear(ref self: Felt252Vec<T>) {
        self.items = Default::default();
        self.len = 0;
    }
}

trait Reserve<V> {
    fn reserve(ref self: V, size: usize);
}

impl Felt252VecReserve<
    T, +Felt252DictValue<T>, +Drop<Felt252Dict<T>>, +Drop<Felt252Vec<T>>
> of Reserve<Felt252Vec<T>> {
    fn reserve(ref self: Felt252Vec<T>, size: usize) { // no-op
    }
}

impl SpanIntoVec<T, V, impl VecTraitImpl: VecTrait<V, T>, +Drop<V>, +Copy<T>> of Into<Span<T>, V> {
    fn into(self: Span<T>) -> V {
        let mut i: usize = 0;
        let len = self.len();
        let mut vec = VecTrait::<V, T>::new();

        loop {
            if i == len {
                break;
            }

            vec.push(*self.at(i));

            i += 1;
        };

        vec
    }
}
