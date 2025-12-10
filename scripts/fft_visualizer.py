#!/usr/bin/env python3
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

def bit_reverse_indices(N: int) -> np.ndarray:
    """
    Return an array of length N where each entry is the bit-reversed index.
    N must be a power of 2.
    """
    if N & (N - 1):
        raise ValueError("N must be a power of 2 for bit-reversal")
    nbits = int(np.log2(N))
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
    N = x.shape[0]
    idx = bit_reverse_indices(N)
    return x[idx]


def main():
    parser = argparse.ArgumentParser(
        description="Visualize magnitude of a complex FFT .mem file (no FFT computation)."
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
        "--bitrev",
        action="store_true",
        help="Bit-reverse the bin order before plotting (for DIT HW output).",
    )
    parser.add_argument(
        "--title",
        default=None,
        help="Figure title (optional).",
    )

    args = parser.parse_args()

    print(f"[INFO] Loading FFT data from {args.mem_file}")
    X = load_mem_file(args.mem_file)
    N = len(X)
    print(f"[INFO] Loaded {N} complex bins.")

    if args.bitrev:
        print("[INFO] Applying bit-reversal to bin order.")
        X = bit_reverse_array(X)

    mag = np.abs(X)

    if args.half:
        k = np.arange(N // 2)
        mag_plot = mag[: N // 2]
    else:
        k = np.arange(N)
        mag_plot = mag

    # Frequency axis if fs provided
    if args.fs is not None:
        fs = args.fs
        x_axis = k * fs / N
        x_label = "Frequency (Hz)"
        print(f"[INFO] Using fs = {fs} Hz for x-axis.")
    else:
        x_axis = k
        x_label = "Bin index k"
        print("[INFO] No fs provided; x-axis uses bin indices.")

    # ---------------- Plotting: magnitude only ----------------
    plt.figure(figsize=(10, 5))
    if args.title is not None:
        plt.title(args.title)
    else:
        plt.title(f"Magnitude Spectrum ({args.mem_file})")
    
    if args.bitrev:
        # filter out low values for better visualization
        mean = np.mean(mag_plot)
        var = np.var(mag_plot)
        threshold = mean + 1.5 * np.sqrt(var)
        mag_plot = np.where(mag_plot < threshold, 0, mag_plot)
    
    plt.plot(x_axis, mag_plot)
    plt.xlabel(x_label)
    plt.ylabel("Magnitude")
    plt.grid(True)

    out_suffix = "_mag_bitreversed.png" if args.bitrev else "_mag.png"
    out_png = args.mem_file.replace(".mem", out_suffix)
    plt.tight_layout()
    plt.savefig(out_png)
    print(f"[INFO] Saved magnitude figure to {out_png}")


if __name__ == "__main__":
    main()
