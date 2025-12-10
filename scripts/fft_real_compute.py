#!/usr/bin/env python3

import argparse
import numpy as np
from typing import List

# Reuse same Q1.15 format as fft_compute.py, but keep this file standalone.
FRAC_BITS = 15
SCALE     = 1 << FRAC_BITS
MIN_Q15   = -(1 << 15)
MAX_Q15   =  (1 << 15) - 1


def parse_hex_line(line: str) -> int:
    line = line.strip()
    if not line:
        return 0
    if line.lower().startswith("0x"):
        return int(line, 16)
    return int(line, 16)


def q15_from_word32(word: int) -> complex:
    real_raw = (word >> 16) & 0xFFFF
    imag_raw = word & 0xFFFF

    if real_raw & 0x8000:
        real_raw -= 0x10000
    if imag_raw & 0x8000:
        imag_raw -= 0x10000

    return complex(real_raw / SCALE, imag_raw / SCALE)


def word32_from_q15(real_val: float, imag_val: float) -> int:
    r = int(np.round(real_val * SCALE))
    i = int(np.round(imag_val * SCALE))

    r = max(MIN_Q15, min(MAX_Q15, r))
    i = max(MIN_Q15, min(MAX_Q15, i))

    if r < 0:
        r = (1 << 16) + r
    if i < 0:
        i = (1 << 16) + i

    return ((r & 0xFFFF) << 16) | (i & 0xFFFF)


def load_mem_file(path: str) -> np.ndarray:
    words: List[int] = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            words.append(parse_hex_line(line))

    data = np.zeros(len(words), dtype=np.complex128)
    for i, w in enumerate(words):
        data[i] = q15_from_word32(w)
    return data


def write_mem_file(path: str, data: np.ndarray):
    with open(path, "w") as f:
        for c in data:
            word = word32_from_q15(c.real, c.imag)
            f.write(f"{word:08X}\n")


def compute_fft_real(x: np.ndarray) -> np.ndarray:
    """Wrapper for numpy.fft.fft on complex float array."""
    return np.fft.fft(x)


def main():
    parser = argparse.ArgumentParser(
        description="NumPy FFT on Q1.15 .mem input."
    )
    parser.add_argument(
        "--in_mem",
        required=True,
        help="Input time-domain .mem (Q1.15 complex)."
    )
    parser.add_argument(
        "--out_mem",
        default="fft_np_out.mem",
        help="Output .mem path for numpy FFT result (Q1.15 complex)."
    )
    parser.add_argument(
        "--n",
        type=int,
        default=None,
        help="FFT length N (optional; defaults to file length)."
    )
    args = parser.parse_args()

    x = load_mem_file(args.in_mem)
    N_file = len(x)

    if args.n is not None and args.n != N_file:
        print(f"[WARN] Provided N={args.n}, but file has {N_file} samples. Using N={N_file}.")
    N = N_file

    print(f"[INFO] Running numpy FFT, N={N}")
    X = compute_fft_real(x)

    print(f"[INFO] Writing numpy FFT result to {args.out_mem}")
    write_mem_file(args.out_mem, X)
    print("[INFO] Done.")

if __name__ == "__main__":
    main()
