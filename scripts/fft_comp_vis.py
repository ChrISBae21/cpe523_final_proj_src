#!/usr/bin/env python3
"""
fft_visualize.py

Given a time-domain Q1.15 .mem file:

  1. Load it as complex float.
  2. Compute:
       - NumPy FFT: X_np (normalized by 1/N)
       - DIT FFT (paper-style): X_dit (fixed-point reference)
  3. Print error metrics between X_np and X_dit.
  4. Plot ONLY the magnitude spectra |X_np[k]| and |X_dit[k]|,
     in two side-by-side subplots (not overlapped).

Usage examples:

  python fft_visualize.py --time_mem sine_time.mem
  python fft_visualize.py --time_mem sine_time.mem --fs 20000 --half
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt

from fft_compute import load_mem_file, compute_fft_dit
from fft_real_compute import compute_fft_real


def main():
    parser = argparse.ArgumentParser(
        description="Visualize magnitude of NumPy vs DIT FFT from time-domain .mem."
    )
    parser.add_argument(
        "--time_mem",
        required=True,
        help="Input time-domain .mem file (Q1.15 complex)."
    )
    parser.add_argument(
        "--fs",
        type=float,
        default=None,
        help="Sampling frequency in Hz (optional, for x-axis in Hz)."
    )
    parser.add_argument(
        "--half",
        action="store_true",
        help="Plot only first N/2 bins (positive frequencies)."
    )
    parser.add_argument(
        "--title",
        default="FFT Magnitude: NumPy vs DIT",
        help="Figure title."
    )
    args = parser.parse_args()

    # ---------------- Load time-domain data ----------------
    print(f"[INFO] Loading time-domain data from {args.time_mem}")
    x = load_mem_file(args.time_mem)
    N = len(x)
    print(f"[INFO] N = {N}")

    # ---------------- Compute both FFTs ----------------
    print("[INFO] Computing NumPy FFT...")
    X_np = compute_fft_real(x)   # likely np.fft.fft(x) inside
    # Normalize NumPy FFT to match 1/N convention
    X_np = X_np / N

    print("[INFO] Computing DIT FFT (paper-style)...")
    X_dit = compute_fft_dit(x)

    # ---------------- Error metrics ----------------
    diff = X_np - X_dit
    abs_err = np.abs(diff)
    max_err  = np.max(abs_err)
    mean_err = np.mean(abs_err)
    rms_err  = np.sqrt(np.mean(abs_err**2))

    print("[RESULT] NumPy vs DIT FFT (NumPy normalized by 1/N):")
    print(f"  max |diff|  = {max_err:.6e}")
    print(f"  mean |diff| = {mean_err:.6e}")
    print(f"  RMS  |diff| = {rms_err:.6e}")

    # ---------------- Choose bins / frequency axis ----------------
    if args.half:
        k = np.arange(N // 2)
        X_np_plot  = X_np[:N // 2]
        X_dit_plot = X_dit[:N // 2]
    else:
        k = np.arange(N)
        X_np_plot  = X_np
        X_dit_plot = X_dit

    if args.fs is not None:
        fs = args.fs
        x_axis = k * fs / N
        x_label = "Frequency (Hz)"
        print(f"[INFO] Using fs = {fs} Hz for x-axis.")
    else:
        x_axis = k
        x_label = "Bin index"
        print("[INFO] No fs provided; x-axis is bin index.")

    mag_np  = np.abs(X_np_plot)
    mag_dit = np.abs(X_dit_plot)

    # ---------------- Plotting: side-by-side magnitude ----------------
    fig, (ax1, ax2) = plt.subplots(
        1, 2, figsize=(12, 5), sharey=True
    )
    fig.suptitle(args.title, fontsize=14)

    # Left: NumPy
    ax1.plot(x_axis, mag_np)
    ax1.set_title("NumPy FFT |X_np[k]| (normalized)")
    ax1.set_xlabel(x_label)
    ax1.set_ylabel("Magnitude")
    ax1.grid(True)

    # Right: DIT
    ax2.plot(x_axis, mag_dit)
    ax2.set_title("DIT FFT |X_dit[k]|")
    ax2.set_xlabel(x_label)
    ax2.grid(True)

    plt.tight_layout(rect=[0, 0.03, 1, 0.95])

    out_png = args.time_mem.replace(".mem", "_fft_mag_compare_side_by_side.png")
    plt.savefig(out_png)
    print(f"[INFO] Saved magnitude comparison figure to {out_png}")

    # plt.show()


if __name__ == "__main__":
    main()
