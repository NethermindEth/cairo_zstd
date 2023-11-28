const path = require("path");
const { readFile, readdir, stat, unlink, writeFile } = require("fs/promises");

const INPUT_DIR = "./data/decode_corpus";
const OUTPUT_DIR = "./src/tests/decode_corpus";
const MAX_SIZE_BYTES = 1 * 1024; // 1 KiB

async function generateDecodingTestFile(filename) {
    const originalPath = path.join(INPUT_DIR, filename);
    const compressedPath = path.join(INPUT_DIR, `${filename}.zst`);
    const outputPath = path.join(OUTPUT_DIR, `${filename}.cairo`);

    const [originalContent, compressedContent] = await Promise.all([
        readFile(originalPath),
        readFile(compressedPath),
    ]);

    await writeFile(outputPath, [
        "// auto-generated file",
        "",
        "use cairo_zstd::tests::decoding::_test_decode;",
        "use cairo_zstd::utils::byte_array::U8SpanIntoByteArray;",
        "",
        `fn get_compressed() -> ByteArray {`,
        "    array![",
        `        ${(compressedContent.toString("hex").match(/.{1,2}/g) || []).map(byte => `0x${byte}`)}`,
        "    ].span().into()",
        "}",
        "",
        `fn get_original() -> ByteArray {`,
        "    array![",
        `        ${(originalContent.toString("hex").match(/.{1,2}/g) || []).map(byte => `0x${byte}`)}`,
        "    ].span().into()",
        "}",
        "",
        "#[test]",
        "#[available_gas(200000000000)]",
        `fn test_decode_${filename}() {`,
        "    _test_decode(@get_compressed(), @get_original());",
        "}",
        "",
    ].join("\n"));
}

async function main() {
    console.log(`Generating tests for zst files at or below ${MAX_SIZE_BYTES} bytes...`);

    await Promise.all(
        (await readdir(OUTPUT_DIR)).map(filename => unlink(path.join(OUTPUT_DIR, filename)))
    );

    const files = (await readdir(INPUT_DIR)).filter(filename => !filename.endsWith(".zst"));

    await Promise.all(
        files.map(async filename => {
            const size = (await stat(path.join(INPUT_DIR, filename))).size;

            if (size > MAX_SIZE_BYTES) {
                return;
            }

            await generateDecodingTestFile(filename);
        })
    );

    await writeFile(`${OUTPUT_DIR}.cairo`, [
        "// auto-generated file",
        "",
        ...(await readdir(OUTPUT_DIR)).map(filename => `mod ${filename.replace(".cairo", "")};`),
        "",
    ].join("\n"));

    console.log("Done!");
}

main();
