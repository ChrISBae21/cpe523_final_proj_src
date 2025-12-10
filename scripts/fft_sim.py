"""
fft_compute.py  (paper-style fixed-point FFT)

Use this to:
  1. Read an initial memory file (complex Q1.15 samples, 32-bit packed hex).
  2. Compute the FFT in Python using the SAME style as the tutorial / hardware:
       - radix-2 DIT
       - Q1.15 fixed-point
       - quantized twiddles
       - in-place, bit-reversed output
  3. Write the expected FFT output to a .mem file in the same packed format.
  4. Optionally compare against a hardware output .mem file.

Assumed memory file format:
  - One 32-bit hex word per line (e.g. 89AB12CD, or 0x89AB12CD).
  - Upper 16 bits: REAL part (signed Q1.15).
  - Lower 16 bits: IMAG part (signed Q1.15).
"""

import argparse
import math
import numpy as np
from typing import Tuple, List

FRAC_BITS = 15          # Q1.15 format
WORD_BITS = 16
SCALE     = 1 << FRAC_BITS  # 2^15
MIN_Q15   = - (1 << 15)
MAX_Q15   = (1 << 15) - 1


# --------------------------
# Basic helpers
# --------------------------

def parse_hex_line(line: str) -> int:
    """Parse a single hex line, allow optional 0x prefix."""
    line = line.strip()
    if not line:
        return 0
    if line.lower().startswith("0x"):
        return int(line, 16)
    return int(line, 16)


def to_int16(x: int) -> int:
    """Wrap integer to signed 16-bit (2's complement)."""
    x &= 0xFFFF
    if x & 0x8000:
        x -= 0x10000
    return x


def q15_from_word32(word: int) -> complex:
    """
    Unpack a 32-bit word into a complex number (float),
    assuming:
        [31:16] = real (Q1.15 signed)
        [15:0]  = imag (Q1.15 signed)
    """
    real_raw = (word >> 16) & 0xFFFF
    imag_raw = word & 0xFFFF

    real_raw = to_int16(real_raw)
    imag_raw = to_int16(imag_raw)

    real_val = real_raw / SCALE
    imag_val = imag_raw / SCALE
    return complex(real_val, imag_val)


def word32_from_q15(real_val: float, imag_val: float) -> int:
    """
    Pack float real/imag into a 32-bit word in Q1.15.
    Clamps to [-32768, 32767] before packing.
    """
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


# --------------------------
# Fixed-point FFT helpers
# --------------------------

def gen_twiddles_q15(N: int) -> List[Tuple[int, int]]:
    """
    Generate Q1.15 twiddles W_N^k for k = 0..N/2-1:

        W_N^k = exp(-j 2π k / N)
    """
    table: List[Tuple[int, int]] = []
    half = N // 2
    for k in range(half):
        angle = -2.0 * math.pi * k / N
        w = complex(math.cos(angle), math.sin(angle))
        r = int(round(w.real * SCALE))
        i = int(round(w.imag * SCALE))

        # Wrap to Q1.15 range as signed 16-bit
        r = to_int16(r)
        i = to_int16(i)
        table.append((r, i))
    return table


def c_add_q15(a: Tuple[int, int], b: Tuple[int, int]) -> Tuple[int, int]:
    ar, ai = a
    br, bi = b
    return to_int16(ar + br), to_int16(ai + bi)


def c_sub_q15(a: Tuple[int, int], b: Tuple[int, int]) -> Tuple[int, int]:
    ar, ai = a
    br, bi = b
    return to_int16(ar - br), to_int16(ai - bi)


def c_mul_q15(a: Tuple[int, int], b: Tuple[int, int]) -> Tuple[int, int]:
    """
    (ar + j ai) * (br + j bi) in Q1.15:
      - 16x16->32-bit products
      - sum/sub
      - arithmetic >> FRAC_BITS
      - wrap to 16 bits (no saturation).
    """
    ar, ai = a
    br, bi = b

    # 32-bit intermediate
    ar_br = ar * br
    ai_bi = ai * bi
    ar_bi = ar * bi
    ai_br = ai * br

    pr_wide = ar_br - ai_bi   # real part wide
    pi_wide = ar_bi + ai_br   # imag part wide

    # Arithmetic shift back to Q1.15
    pr = pr_wide >> FRAC_BITS
    pi = pi_wide >> FRAC_BITS

    # Wrap to 16-bit
    return to_int16(pr), to_int16(pi)


def compute_fft_fixed_paper_style(data: np.ndarray) -> np.ndarray:
    """
    Compute FFT using the same style as the tutorial / hardware:
      - radix-2 DIT
      - Q1.15 fixed point
      - quantized twiddles
      - in-place (bit-reversed output), no reordering

    `data` is a numpy complex float array (from q15_from_word32).
    Returns a numpy complex float array representing the final Q1.15 contents
    (converted back to float for convenience).
    """
    N = len(data)
    if N & (N - 1) != 0:
        raise ValueError("FFT length must be a power of 2")

    # Convert to Q1.15 ints
    buf: List[Tuple[int, int]] = []
    for c in data:
        r = int(round(c.real * SCALE))
        i = int(round(c.imag * SCALE))
        r = max(MIN_Q15, min(MAX_Q15, r))
        i = max(MIN_Q15, min(MAX_Q15, i))
        buf.append((to_int16(r), to_int16(i)))

    # Precompute twiddles W_N^k for k=0..N/2-1
    twiddles = gen_twiddles_q15(N)

    num_stages = int(math.log2(N))

    for stage in range(num_stages):
        stride     = 1 << stage          # 2^stage
        group_size = stride << 1         # 2^(stage+1)
        num_groups = N // group_size
        tw_step    = N // group_size     # N / (2^(stage+1))

        for g in range(num_groups):
            base = g * group_size
            for j in range(stride):
                a = base + j
                b = a + stride

                exp = j * tw_step        # twiddle exponent
                # We only stored k in [0..N/2-1], so take exp mod (N/2)
                idx = exp % (N // 2)
                W = twiddles[idx]

                A = buf[a]
                B = buf[b]

                T  = c_mul_q15(B, W)
                Ap = c_add_q15(A, T)
                Bp = c_sub_q15(A, T)

                buf[a] = Ap
                buf[b] = Bp

    # Convert final Q1.15 buffer back to float complex
    out = np.zeros(N, dtype=np.complex128)
    for n, (r, i) in enumerate(buf):
        out[n] = complex(r / SCALE, i / SCALE)

    return out


def main():
    parser = argparse.ArgumentParser(description="FFT reference checker (paper-style fixed-point)")
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
        "--N",
        type=int,
        default=None,
        help="FFT length (optional; defaults to length of in_mem)."
    )
    args = parser.parse_args()

    # Load input
    print(f"[INFO] Loading input memory from {args.in_mem}")
    data_in = load_mem_file(args.in_mem)
    print(f"[INFO] Loaded {len(data_in)} complex samples.")

    if args.N is not None and args.N != len(data_in):
        print(f"[WARN] Provided N={args.N}, but file has {len(data_in)} samples. "
              f"Using N={len(data_in)} (file length).")

    N = len(data_in)

    # Compute FFT in fixed-point, paper-style
    print(f"[INFO] Computing fixed-point FFT of length {N} (paper-style)...")
    fft_out = compute_fft_fixed_paper_style(data_in)

    # Write reference output
    print(f"[INFO] Writing expected FFT output to {args.out_ref_mem}")
    write_mem_file(args.out_ref_mem, fft_out)

    print("[INFO] Done.")


if __name__ == "__main__":
    main()
