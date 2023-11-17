mod blocks;
mod decoding;
mod fse;
mod huff0;
mod utils;
mod frame;
mod frame_decoder;

#[cfg(test)]
mod tests;

// This is a nice example, so why removing it until we have our own main? 
fn main() -> felt252 {
    fib(16)
}

fn fib(mut n: felt252) -> felt252 {
    let mut a: felt252 = 0;
    let mut b: felt252 = 1;
    loop {
        if n == 0 {
            break a;
        }
        n = n - 1;
        let temp = b;
        b = a + b;
        a = temp;
    }
}
