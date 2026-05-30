#!/usr/bin/env python3
import argparse
import os
import struct
import sys


SPARSE_HEADER_MAGIC = 0xED26FF3A
CHUNK_TYPE_RAW = 0xCAC1
CHUNK_TYPE_DONT_CARE = 0xCAC3


def is_all_zero(data: bytes) -> bool:
    return not data or data.count(0) == len(data)


def sparse_header(block_size, total_blocks, total_chunks):
    return struct.pack(
        "<IHHHHIIII",
        SPARSE_HEADER_MAGIC,
        1,
        0,
        28,
        12,
        block_size,
        total_blocks,
        total_chunks,
        0,
    )


def write_chunk(out_file, chunk_type, blocks, payload=b""):
    total_size = 12 + len(payload)
    out_file.write(struct.pack("<HHII", chunk_type, 0, blocks, total_size))
    if payload:
        out_file.write(payload)


def main():
    parser = argparse.ArgumentParser(description="Convert a raw disk image to Android sparse image format.")
    parser.add_argument("--input", required=True, help="Raw input image.")
    parser.add_argument("--output", required=True, help="Android sparse output image.")
    parser.add_argument("--block-size", type=int, default=4096)
    parser.add_argument("--strip-trailing-bytes", type=int, default=0, help="Ignore this many bytes from the end of input.")
    parser.add_argument("--max-raw-blocks", type=int, default=1024, help="Maximum RAW chunk size in blocks.")
    args = parser.parse_args()

    if args.block_size <= 0 or args.block_size % 4 != 0:
        raise SystemExit("--block-size must be a positive multiple of 4")

    input_size = os.path.getsize(args.input) - args.strip_trailing_bytes
    if input_size <= 0:
        raise SystemExit("input size after stripping must be positive")

    total_blocks = (input_size + args.block_size - 1) // args.block_size
    chunk_count = 0

    with open(args.input, "rb") as src, open(args.output, "wb") as out_file:
        out_file.write(sparse_header(args.block_size, total_blocks, 0))
        block_index = 0
        pending_raw = bytearray()
        pending_raw_blocks = 0

        def flush_raw():
            nonlocal pending_raw, pending_raw_blocks, chunk_count
            if pending_raw_blocks:
                write_chunk(out_file, CHUNK_TYPE_RAW, pending_raw_blocks, pending_raw)
                chunk_count += 1
                pending_raw = bytearray()
                pending_raw_blocks = 0

        while block_index < total_blocks:
            remaining_bytes = input_size - (block_index * args.block_size)
            to_read = min(args.block_size, remaining_bytes)
            data = src.read(to_read)
            if len(data) < args.block_size:
                data += b"\0" * (args.block_size - len(data))

            if is_all_zero(data):
                flush_raw()
                dont_care_blocks = 1
                block_index += 1

                while block_index < total_blocks:
                    pos = src.tell()
                    remaining_bytes = input_size - (block_index * args.block_size)
                    to_read = min(args.block_size, remaining_bytes)
                    next_data = src.read(to_read)
                    if len(next_data) < args.block_size:
                        next_data += b"\0" * (args.block_size - len(next_data))
                    if not is_all_zero(next_data):
                        src.seek(pos)
                        break
                    dont_care_blocks += 1
                    block_index += 1

                write_chunk(out_file, CHUNK_TYPE_DONT_CARE, dont_care_blocks)
                chunk_count += 1
                continue

            pending_raw.extend(data)
            pending_raw_blocks += 1
            block_index += 1
            if pending_raw_blocks >= args.max_raw_blocks:
                flush_raw()

        flush_raw()

        out_file.seek(0)
        out_file.write(sparse_header(args.block_size, total_blocks, chunk_count))

    print(f"input_bytes={input_size}")
    print(f"total_blocks={total_blocks}")
    print(f"chunks={chunk_count}")
    print(f"output={args.output}")
    print(f"output_bytes={os.path.getsize(args.output)}")


if __name__ == "__main__":
    main()
