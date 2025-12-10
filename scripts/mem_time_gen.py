"""
gen_ramA_init.py

Generate an initial RAM file for FFT testing.

- Output format: one 32-bit hex word per line
    REAL[31:16] = signed Q1.15
    IMAG[15:0]  = signed Q1.15

- Patterns:
    impulse : x[0] = 1.0, others = 0
    sine    : single-tone sine wave at bin k
    noise   : uniform noise in [-0.5, 0.5)

Usage examples:

    # Default: impulse, N=1024, ramA_init.mem
    python gen_ramA_init.py

    # Sine wave at bin 5, N=1024
    python gen_ramA_init.py --pattern sine --k 5 --amp 0.8

    # Noise, different length, custom file
    python gen_ramA_init.py --pattern noise --N 256 --out ramA_init_256.mem
"""

import argparse
import math
import numpy as np


FRAC = 15
SCALE = 1 << FRAC
MIN_Q15 = - (1 << 15)
MAX_Q15 = (1 << 15) - 1


def to_q15(x: float) -> int:
    """Convert float in roughly [-1,1) to signed Q1.15, return 16-bit two's complement."""
    v = int(round(x * SCALE))
    if v < MIN_Q15:
        v = MIN_Q15
    if v > MAX_Q15:
        v = MAX_Q15
    if v < 0:
        v = (1 << 16) + v
    return v & 0xFFFF


def gen_impulse(N: int) -> np.ndarray:
    sig = np.zeros(N, dtype=float)
    sig[0] = 1.0
    print(f"[INFO] Pattern: impulse (x[0]=1.0, others=0)")
    return sig


def gen_sine(N: int, k: int, amp: float) -> np.ndarray:
    n = np.arange(N, dtype=float)
    sig = amp * np.sin(2.0 * math.pi * k * n / N)
    print(f"[INFO] Pattern: sine wave, bin k={k}, amplitude={amp}")
    return sig


def gen_noise(N: int) -> np.ndarray:
    rng = np.random.default_rng(seed=1234)
    sig = rng.uniform(low=-0.5, high=0.5, size=N)
    print(f"[INFO] Pattern: noise in [-0.5, 0.5), seed=1234")
    return sig


def write_mem_file(path: str, real: np.ndarray, imag: np.ndarray):
    """Write packed Q1.15 complex samples to a .mem file."""
    assert len(real) == len(imag)
    N = len(real)
    with open(path, "w") as f:
        for r, i in zip(real, imag):
            qr = to_q15(float(r))
            qi = to_q15(float(i))
            word = ((qr & 0xFFFF) << 16) | (qi & 0xFFFF)
            f.write(f"{word:08X}\n")
    print(f"[INFO] Wrote {N} samples to '{path}'")


def main():
    parser = argparse.ArgumentParser(description="Generate ramA_init.mem for FFT testing")
    parser.add_argument(
        "--pattern",
        type=str,
        default="impulse",
        choices=["impulse", "sine", "noise"],
        help="Input pattern: impulse | sine | noise (default: impulse)",
    )
    parser.add_argument(
        "--out",
        type=str, 
        default="ramA_init.mem",
        help="Output .mem filename (default: ramA_init.mem)",
    )
    parser.add_argument(
        "--N",
        type=int,
        default=1024,
        help="Number of samples / FFT length (default: 1024)",
    )
    parser.add_argument(
        "--k",
        type=int,
        default=5,
        help="Sine bin index (used only for pattern == sine, default: 5)",
    )
    parser.add_argument(
        "--amp",
        type=float,
        default=0.8,
        help="Sine amplitude (used only for pattern == sine, default: 0.8)",
    )

    args = parser.parse_args()

    N = args.N
    pattern = args.pattern

    # Generate real part based on pattern
    if pattern == "impulse":
        real = gen_impulse(N)
    elif pattern == "sine":
        real = gen_sine(N, args.k, args.amp)
    elif pattern == "noise":
        real = gen_noise(N)
    else:
        raise ValueError(f"Unknown pattern: {pattern}")

    # Imaginary part = 0 for all samples (real input)
    imag = np.zeros_like(real)

    # Write packed Q1.15 mem file
    write_mem_file(args.out, real, imag)


if __name__ == "__main__":
    main()
