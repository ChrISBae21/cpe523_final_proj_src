#!/usr/bin/env python3
"""
fft_compute.py

Compute a radix-2 DIT FFT that mirrors the "paper-style" algorithm:

- Stages s = 0 .. log2(N)-1
- stride     = 2^s
- group_size = 2^(s+1)
- tw_step    = N / group_size
- twiddle exponent = j * tw_step, j in [0..stride-1]

This matches your AGU logic:

    stride     = 1 << stage
    group_size = stride << 1
    tw_step    = N >> (stage + 1)
    exp        = j * tw_step

CLI:
    python fft_compute.py --in_mem sine_time.mem --out_ref_mem sine_freq_dit.mem --n 1024
"""

import argparse
import math
import numpy as np
from typing import Tuple, List, Union

# Q1.15 constants
FRAC_BITS = 15
SCALE     = 1 << FRAC_BITS
MIN_Q15   = -(1 << 15)
MAX_Q15   =  (1 << 15) - 1


# ----------------------------
# Q1.15 helpers / mem IO
# ----------------------------
def parse_hex_line(line: str) -> int:
    line = line.strip()
    if not line:
        return 0
    if line.lower().startswith("0x"):
        return int(line, 16)
    return int(line, 16)


def q15_from_word32(word: int) -> complex:
    """
    Unpack 32-bit word into complex float:
      [31:16] = real (Q1.15 signed)
      [15:0]  = imag (Q1.15 signed)
    """
    real_raw = (word >> 16) & 0xFFFF
    imag_raw = word & 0xFFFF

    if real_raw & 0x8000:
        real_raw -= 0x10000
    if imag_raw & 0x8000:
        imag_raw -= 0x10000

    real_val = real_raw / SCALE
    imag_val = imag_raw / SCALE
    return complex(real_val, imag_val)


def word32_from_q15(real_val: float, imag_val: float) -> int:
    """
    Pack float real/imag into a 32-bit word in Q1.15, with saturation.
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

def to_int16(x: int) -> int:
    """Wrap integer to signed 16-bit (2's complement)."""
    x &= 0xFFFF
    if x & 0x8000:
        x -= 0x10000
    return x

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


def c_add_q15(a, b):
    ar, ai = a
    br, bi = b
    return to_int16(ar + br), to_int16(ai + bi)

def c_sub_q15(a, b):
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
    return to_int16(pr), to_int16(pi)

def load_mem_file(path: str) -> np.ndarray:
    """Load a .mem file and return a complex numpy array (float)."""
    words: List[int] = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            words.append(parse_hex_line(line))

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


# ----------------------------
# DIT FFT implementation
# ----------------------------
def compute_fft_dit(data: np.ndarray) -> np.ndarray:
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

    # reorder to natural order:
    out_nat = bit_reverse_array(out)
    return out_nat

def bit_reverse_indices(N: int) -> np.ndarray:
    """
    Return an array of length N where each entry is the bit-reversed index.
    N must be a power of 2.
    """
    if N & (N - 1):
        raise ValueError("N must be a power of 2 for bit-reversal")
    nbits = int(math.log2(N))
    rev = np.zeros(N, dtype=int)
    for i in range(N):
        b = i
        r = 0
        for _ in range(nbits):
            r = (r << 1) | (b & 1)
            b >>= 1
        rev[i] = r
    return rev


def bit_reverse_array(x: np.ndarray) -> np.ndarray:
    """
    Return a new array whose elements are reordered in bit-reversed index order.
    x is a 1D numpy array of length N (power of 2).
    """
    N = x.shape[0]
    idx = bit_reverse_indices(N)
    return x[idx]


def bit_reverse_mem(in_mem: str, out_mem: str) -> None:
    """
    Load a .mem file, bit-reverse its *index order*, and write to a new .mem file.
      - in_mem:  path to input .mem (Q1.15 complex)
      - out_mem: path to output .mem (Q1.15 complex, bit-reversed order)
    """
    x = load_mem_file(in_mem)          # complex float array
    x_br = bit_reverse_array(x)
    write_mem_file(out_mem, x_br)
    print(f"[INFO] Bit-reversed '{in_mem}' -> '{out_mem}'")


def bit_reverse_data(data: Union[str, np.ndarray], out_mem: str | None = None) -> np.ndarray:
    """
    Convenience wrapper:

      - If 'data' is a numpy array, return bit-reversed copy of that array.
      - If 'data' is a string (path to .mem), load the file, bit-reverse, and:
          * if out_mem is not None: write to that file
          * always return the bit-reversed array.

    This is handy for both scripts and interactive use.
    """
    if isinstance(data, str):
        x = load_mem_file(data)
        x_br = bit_reverse_array(x)
        if out_mem is not None:
            write_mem_file(out_mem, x_br)
            print(f"[INFO] Bit-reversed '{data}' -> '{out_mem}'")
        return x_br
    else:
        # assume it's already an array
        return bit_reverse_array(data)


# ----------------------------
# CLI
# ----------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Radix-2 DIT FFT (paper-style) on Q1.15 .mem input."
    )
    parser.add_argument(
        "--in_mem",
        required=True,
        help="Input time-domain .mem (Q1.15 complex)."
    )
    parser.add_argument(
        "--out_ref_mem",
        default="fft_dit_out.mem",
        help="Output .mem path for DIT FFT result (Q1.15 complex)."
    )
    parser.add_argument(
        "--n",
        type=int,
        default=None,
        help="FFT length N (optional; defaults to length of in_mem)."
    )
    args = parser.parse_args()

    x = load_mem_file(args.in_mem)
    N_file = len(x)

    if args.n is not None and args.n != N_file:
        print(f"[WARN] Provided N={args.n}, but file has {N_file} samples. Using N={N_file}.")
    N = N_file

    print(f"[INFO] Running DIT FFT, N={N}")
    X = compute_fft_dit(x)

    print(f"[INFO] Writing DIT FFT result to {args.out_ref_mem}")
    write_mem_file(args.out_ref_mem, X)
    print("[INFO] Done.")

if __name__ == "__main__":
    main()
