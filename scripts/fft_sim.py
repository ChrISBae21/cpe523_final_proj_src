"""
fft_check.py

Use this to:
  1. Read an initial memory file (complex Q1.15 samples, 32-bit packed hex).
  2. Compute the FFT in Python (numpy).
  3. Write the expected FFT output to a .mem file in the same packed format.
  4. Optionally compare against a hardware output .mem file.

Assumed memory file format:
  - One 32-bit hex word per line (e.g. 89AB12CD, or 0x89AB12CD).
  - Upper 16 bits: REAL part (signed Q1.15).
  - Lower 16 bits: IMAG part (signed Q1.15).
"""

import argparse
import numpy as np
from typing import Tuple, List


FRAC_BITS = 15          # Q1.15 format
INT_BITS = 1            # sign + integer bit (conceptually)
WORD_BITS = 16
SCALE = 1 << FRAC_BITS  # 2^15
MIN_Q15 = - (1 << 15)
MAX_Q15 = (1 << 15) - 1


def parse_hex_line(line: str) -> int:
    """Parse a single hex line, allow optional 0x prefix."""
    line = line.strip()
    if not line:
        return 0
    if line.lower().startswith("0x"):
        return int(line, 16)
    return int(line, 16)


def q15_from_word32(word: int) -> complex:
    """
    Unpack a 32-bit word into a complex number in float,
    assuming:
        [31:16] = real (Q1.15 signed)
        [15:0]  = imag (Q1.15 signed)
    """
    real_raw = (word >> 16) & 0xFFFF
    imag_raw = word & 0xFFFF

    # Convert 16-bit two's complement to signed int
    if real_raw & 0x8000:
        real_raw -= 0x10000
    if imag_raw & 0x8000:
        imag_raw -= 0x10000

    real_val = real_raw / SCALE
    imag_val = imag_raw / SCALE
    return complex(real_val, imag_val)


def word32_from_q15(real_val: float, imag_val: float) -> int:
    """
    Pack float real/imag into a 32-bit word in Q1.15.
    Clamps to [-32768, 32767].
    """
    # Scale
    r = int(np.round(real_val * SCALE))
    i = int(np.round(imag_val * SCALE))

    # Saturate
    r = max(MIN_Q15, min(MAX_Q15, r))
    i = max(MIN_Q15, min(MAX_Q15, i))

    # Back to unsigned 16-bit two's complement
    if r < 0:
        r = (1 << 16) + r
    if i < 0:
        i = (1 << 16) + i

    return ((r & 0xFFFF) << 16) | (i & 0xFFFF)


def load_mem_file(path: str) -> np.ndarray:
    """Load a .mem file and return a complex numpy array (float)."""
    words: List[int] = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            w = parse_hex_line(line)
            words.append(w)

    data = np.zeros(len(words), dtype=np.complex128)
    for idx, w in enumerate(words):
        data[idx] = q15_from_word32(w)
    return data


def write_mem_file(path: str, data: np.ndarray):
    """
    Write complex data (float) to a .mem file in packed 32-bit Q1.15 format.
    """
    with open(path, "w") as f:
        for c in data:
            word = word32_from_q15(c.real, c.imag)
            f.write(f"{word:08X}\n")


def compute_fft(data: np.ndarray) -> np.ndarray:
    """
    Compute the FFT of the complex data.
    Data is numpy complex float array.
    Returns numpy complex array.
    """
    return np.fft.fft(data)


def compare_results(ref: np.ndarray, hw: np.ndarray) -> Tuple[float, float, float]:
    """
    Compare two complex arrays:
      - max absolute error (magnitude),
      - mean absolute error,
      - RMS error.
    """
    if len(ref) != len(hw):
        raise ValueError(f"Length mismatch: ref={len(ref)}, hw={len(hw)}")

    diff = ref - hw
    abs_err = np.abs(diff)
    max_err = np.max(abs_err)
    mean_err = np.mean(abs_err)
    rms_err = np.sqrt(np.mean(abs_err**2))
    return max_err, mean_err, rms_err


def main():
    parser = argparse.ArgumentParser(description="FFT reference checker for hardware module")
    parser.add_argument(
        "--in_mem",
        required=True,
        help="Input memory file (complex Q1.15, 32-bit packed hex, one per line)."
    )
    parser.add_argument(
        "--out_ref_mem",
        default="fft_expected_out.mem",
        help="Output memory file path for expected FFT result (packed Q1.15)."
    )
    parser.add_argument(
        "--hw_mem",
        default=None,
        help="Optional: hardware output memory file to compare against."
    )
    parser.add_argument(
        "--n",
        type=int,
        default=None,
        help="FFT length (optional; defaults to length of in_mem)."
    )
    args = parser.parse_args()

    # Load input
    print(f"[INFO] Loading input memory from {args.in_mem}")
    data_in = load_mem_file(args.in_mem)
    print(f"[INFO] Loaded {len(data_in)} complex samples.")

    if args.n is not None and args.n != len(data_in):
        print(f"[WARN] Provided N={args.n}, but file has {len(data_in)} samples. "
              f"Using N={len(data_in)} (file length).")

    N = len(data_in)

    # Compute FFT
    print(f"[INFO] Computing FFT of length {N}...")
    fft_out = compute_fft(data_in)

    # Write reference output
    print(f"[INFO] Writing expected FFT output to {args.out_ref_mem}")
    write_mem_file(args.out_ref_mem, fft_out)

    # Optional comparison with hardware result
    if args.hw_mem is not None:
        print(f"[INFO] Loading hardware output from {args.hw_mem}")
        hw_out = load_mem_file(args.hw_mem)

        if len(hw_out) != N:
            print(f"[ERROR] Hardware mem length {len(hw_out)} != input length {N}")
            return

        # Note: hw_out is in Q1.15; fft_out is float and we wrote a quantized
        # version to out_ref_mem. For comparison, quantize fft_out to Q1.15 too:
        fft_q15 = np.zeros_like(fft_out)
        for i in range(N):
            w = word32_from_q15(fft_out[i].real, fft_out[i].imag)
            # convert back to float for fair comparison
            fft_q15[i] = q15_from_word32(w)

        max_err, mean_err, rms_err = compare_results(fft_q15, hw_out)
        print("[RESULT] Comparison vs hardware output:")
        print(f"         Max abs error  : {max_err:.6e}")
        print(f"         Mean abs error : {mean_err:.6e}")
        print(f"         RMS error      : {rms_err:.6e}")

        # Optionally print a few samples for sanity
        print("\n[DEBUG] First 8 bins (ref vs hw):")
        for i in range(min(8, N)):
            print(f"  k={i:2d}: ref={fft_q15[i]: .6f}, hw={hw_out[i]: .6f}, "
                  f"diff={fft_q15[i]-hw_out[i]: .6e}")

    print("[INFO] Done.")


if __name__ == "__main__":
    main()
