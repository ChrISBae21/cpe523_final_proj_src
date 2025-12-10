#!/usr/bin/env python3
"""
fft_visualizer.py

Visualize a single complex Q1.15 .mem file (assumed FFT bins).

Assumes:
  - One 32-bit hex word per line.
  - REAL[31:16] and IMAG[15:0] are signed Q1.15.

Plots:
  1. Magnitude spectrum |X[k]|
  2. Real and imaginary parts vs bin/frequency

No FFT computations are performed. It only reads and visualizes the data.

Usage:
    python fft_visualizer.py --mem_file fft_hw_out.mem
    python fft_visualizer.py --mem_file fft_hw_out.mem --fs 20000 --half
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt

FRAC_BITS = 15
SCALE = 1 << FRAC_BITS


def parse_hex_line(line: str) -> int:
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

    if real_raw & 0x8000:
        real_raw -= 0x10000
    if imag_raw & 0x8000:
        imag_raw -= 0x10000

    real_val = real_raw / SCALE
    imag_val = imag_raw / SCALE
    return complex(real_val, imag_val)


def load_mem_file(path: str) -> np.ndarray:
    """Load a .mem file and return a complex numpy array (float)."""
    words = []
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

def bit_reverse_indices(N: int):
    """Return a list of bit-reversed indices for length N."""
    nbits = int(np.log2(N))
    idx = np.arange(N)
    rev = np.zeros(N, dtype=int)
    for i in range(N):
        b = i
        r = 0
        for _ in range(nbits):
            r = (r << 1) | (b & 1)
            b >>= 1
        rev[i] = r
    return rev



def main():
    parser = argparse.ArgumentParser(
        description="Visualize a complex FFT .mem file (no FFT computed, just plotting)."
    )
    parser.add_argument(
        "--mem_file",
        required=True,
        help="Path to .mem file (complex Q1.15, 32-bit packed per line).",
    )
    parser.add_argument(
        "--fs",
        type=float,
        default=None,
        help="Sampling frequency in Hz (if provided, x-axis is frequency in Hz).",
    )
    parser.add_argument(
        "--half",
        action="store_true",
        help="Plot only first N/2 FFT bins (positive frequencies).",
    )
    parser.add_argument(
        "--title",
        default="FFT Visualization",
        help="Figure title.",
    )
    
    parser.add_argument(
        "--bitrev",
        action="store_true",
        help="Treat input as bit-reversed order and reorder to natural bin order before plotting.",
    )

    args = parser.parse_args()

    print(f"[INFO] Loading FFT data from {args.mem_file}")
    X = load_mem_file(args.mem_file)
    N = len(X)
    print(f"[INFO] Loaded {N} complex bins.")
    
    if args.bitrev:
        if (N & (N - 1)) != 0:
            raise SystemExit("[ERROR] --bitrev only valid for power-of-two length")
        perm = bit_reverse_indices(N)
        X = X[perm]
        print("[INFO] Applied bit-reversal permutation to bins.")

    mag = np.abs(X)
    real = X.real
    imag = X.imag

    if args.half:
        k = np.arange(N // 2)
        mag_plot = mag[: N // 2]
        real_plot = real[: N // 2]
        imag_plot = imag[: N // 2]
    else:
        k = np.arange(N)
        mag_plot = mag
        real_plot = real
        imag_plot = imag

    # Frequency axis if fs provided
    if args.fs is not None:
        fs = args.fs
        freq_axis = k * fs / N
        x_label = "Frequency (Hz)"
        print(f"[INFO] Using fs = {fs} Hz for x-axis.")
    else:
        freq_axis = k
        x_label = "Bin index k"
        print("[INFO] No fs provided; x-axis uses bin indices.")

    # ---------------- Plotting ----------------
    plt.figure(figsize=(12, 8))
    plt.suptitle(args.title, fontsize=14)

    # Magnitude spectrum
    ax1 = plt.subplot(2, 1, 1)
    ax1.plot(freq_axis, mag_plot, label="|X[k]|")
    ax1.set_xlabel(x_label)
    ax1.set_ylabel("Magnitude")
    ax1.set_title("Magnitude spectrum")
    ax1.grid(True)
    ax1.legend()

    # Real/Imag parts
    ax2 = plt.subplot(2, 1, 2)
    ax2.plot(freq_axis, real_plot, label="Re{X[k]}")
    ax2.plot(freq_axis, imag_plot, label="Im{X[k]}", linestyle="--")
    ax2.set_xlabel(x_label)
    ax2.set_ylabel("Amplitude")
    ax2.set_title("Real and Imag parts")
    ax2.grid(True)
    ax2.legend()

    plt.tight_layout(rect=[0, 0.03, 1, 0.95])

    # save figure
    out_png = args.mem_file.replace(".mem", "_fft_visualization.png")
    plt.savefig(out_png)
    print(f"[INFO] Saved figure to {out_png}")


if __name__ == "__main__":
    main()
