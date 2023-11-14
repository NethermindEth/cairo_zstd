#[generate_trait]
impl ArrayPushResizeImpl<T, +Copy<T>, +Drop<T>> of ArrayPushResizeTrait<T> {
    fn push_resize(ref self: Array<T>, new_len: usize, input: T) {
        assert(new_len < self.len(), 'invalid push_resize len');

        let mut i: usize = 0;
        let len = new_len - self.len();
        loop {
            if i >= len {
                break;
            }

            self.append(input);

            i += 1;
        }
    }
}

#[generate_trait]
impl ArrayAppendSpanImpl<T, +Clone<T>, +Drop<T>> of ArrayAppendSpanTrait<T> {
    fn append_span(ref self: Array<T>, mut span: Span<T>) {
        match span.pop_front() {
            Option::Some(current) => {
                self.append(current.clone());
                self.append_span(span);
            },
            Option::None => {}
        };
    }
}
