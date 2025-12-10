#!/usr/bin/env python3

'''
Generate a twiddle ROM .mem file for a radix-2 FFT.
'''


import argparse
import numpy as np


def to_int16_wrap(x: np.ndarray) -> np.ndarray:
    """
    Wrap integer array to signed 16-bit two's complement.
    """
    x = x.astype(int)
    x = np.where(x < 0, x + (1 << 16), x)  # map negative to 2's complement
    return x & 0xFFFF                      # keep 16 bits


def gen_twiddles_q_format(N: int, frac_bits: int) -> np.ndarray:
    if N & (N - 1) != 0:
        raise ValueError("N must be a power of 2 for radix-2 FFT.")

    k = np.arange(N // 2)
    W = np.exp(-2j * np.pi * k / N)  # e^{-j2πk/N}

    scale = 1 << frac_bits

    # Scale to Q1.frac_bits
    Wr = np.round(np.real(W) * scale).astype(int)
    Wi = np.round(np.imag(W) * scale).astype(int)

    # Wrap to 16-bit signed two's complement
    Wr16 = to_int16_wrap(Wr)
    Wi16 = to_int16_wrap(Wi)

    # Pack into 32-bit words: [31:16]=real, [15:0]=imag
    words = (Wr16.astype(np.uint32) << 16) | Wi16.astype(np.uint32)
    return words


def write_mem_file(path: str, words: np.ndarray):
    """
    Write 32-bit words to a .mem file as 8 hex digit lines.
    """
    with open(path, "w") as f:
        for w in words:
            f.write(f"{int(w):08X}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Generate twiddle ROM .mem file for radix-2 FFT."
    )
    parser.add_argument(
        "--N",
        type=int,
        required=True,
        help="FFT length N (must be a power of 2).",
    )
    parser.add_argument(
        "--frac_bits",
        type=int,
        default=15,
        help="Number of fractional bits for Q1.frac_bits (default: 15 for Q1.15).",
    )
    parser.add_argument(
        "--outfile",
        default="twiddle_rom.mem",
        help="Output .mem file path (default: twiddle_rom.mem).",
    )

    args = parser.parse_args()

    N = args.N
    frac_bits = args.frac_bits
    outfile = args.outfile

    print(f"[INFO] Generating twiddles for N={N}, frac_bits={frac_bits}...")
    words = gen_twiddles_q_format(N, frac_bits)
    print(f"[INFO] Generated {len(words)} twiddle entries (N/2).")

    print(f"[INFO] Writing to {outfile}")
    write_mem_file(outfile, words)

    print("[INFO] Done.")


if __name__ == "__main__":
    main()
