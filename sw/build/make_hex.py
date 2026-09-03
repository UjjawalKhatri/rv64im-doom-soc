import sys

def bin_to_hex(bin_path, hex_path, max_bytes=8192):
    with open(bin_path, 'rb') as f:
        data = f.read()

    print(f"[HEX GEN] Read {len(data)} bytes from {bin_path}")

    # Pad data to multiple of 4 bytes
    pad_len = (4 - (len(data) % 4)) % 4
    data += b'\x00' * pad_len

    num_words = max_bytes // 4  # 8192 bytes = 2048 32-bit words

    with open(hex_path, 'w') as f:
        for i in range(num_words):
            byte_idx = i * 4
            if byte_idx + 3 < len(data):
                b0 = data[byte_idx]
                b1 = data[byte_idx + 1]
                b2 = data[byte_idx + 2]
                b3 = data[byte_idx + 3]
                word_val = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            else:
                # Default NOP instruction (addi x0, x0, 0 = 0x00000013)
                word_val = 0x00000013
            f.write(f"{word_val:08x}\n")

    print(f"[HEX GEN] Successfully generated {num_words} 32-bit words ({max_bytes} bytes) in {hex_path}")

def bin_to_data_hex(bin_path, hex_path, max_bytes=8192):
    with open(bin_path, 'rb') as f:
        data = f.read()

    # Pad data to multiple of 8 bytes
    pad_len = (8 - (len(data) % 8)) % 8
    data += b'\x00' * pad_len

    num_words = max_bytes // 8  # 8192 bytes = 1024 64-bit words

    with open(hex_path, 'w') as f:
        for i in range(num_words):
            byte_idx = i * 8
            if byte_idx + 7 < len(data):
                b0 = data[byte_idx]
                b1 = data[byte_idx + 1]
                b2 = data[byte_idx + 2]
                b3 = data[byte_idx + 3]
                b4 = data[byte_idx + 4]
                b5 = data[byte_idx + 5]
                b6 = data[byte_idx + 6]
                b7 = data[byte_idx + 7]
                word_val = (b7 << 56) | (b6 << 48) | (b5 << 40) | (b4 << 32) | (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            else:
                word_val = 0x0
            f.write(f"{word_val:016x}\n")

    print(f"[DATA GEN] Successfully generated {num_words} 64-bit words ({max_bytes} bytes) in {hex_path}")

if __name__ == "__main__":
    bin_file = sys.argv[1] if len(sys.argv) > 1 else "sw/doom_test.bin"
    hex_file = sys.argv[2] if len(sys.argv) > 2 else "instructions.mem"
    bin_to_hex(bin_file, hex_file)
    bin_to_data_hex(bin_file, "data.mem")
