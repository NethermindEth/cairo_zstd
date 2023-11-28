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

### Testing

In order to generate the decode corpus test files, first run the test
generation script:

```
node ./script/generate_decode_corpus_tests.js
```

This will generate a decoding test for each of the files in
`data/decode_corpus` which are at or below the set file size in the script.
The test generation is a temporary workaround to embed the original/compressed
file contents in a cairo file while we're not using a runner that supports a
read file-like cheatcode for testing.

At this point, simply run:

```
scarb test
```
