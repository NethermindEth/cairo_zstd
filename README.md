# cairo-zstd

This is a Cairo v1 port of a zstd decompressor. The code is heavily and purposely based on the [zstd-rs](https://github.com/KillingSpark/zstd-rs)
project, except that it's now [Cairo](https://github.com/starkware-libs/cairo).

STARK-provable decompression here we go!

Still a WIP.

### Current development state

- [x] Main implementation porting
- [x] Decoding tests
- [ ] Dictionary support
- [ ] Optimizations and benchmarking
