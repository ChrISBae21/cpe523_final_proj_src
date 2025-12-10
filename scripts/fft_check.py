#!/usr/bin/env python3
"""
fft_check.py

Compare two complex Q1.15 .mem files (same 32-bit packed format):

  REAL[31:16] = signed Q1.15
  IMAG[15:0]  = signed Q1.15

No FFT computations are performed. This is just a comparator:
  - ref_mem: reference / golden output
  - dut_mem: DUT / hardware output

Usage:
    python fft_check.py --ref ref_fft.mem --dut fft_hw_out.mem
"""

import argparse
import numpy as np

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

    # two's complement to signed
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


def compare_results(ref: np.ndarray, dut: np.ndarray):
    if len(ref) != len(dut):
        print(f"[WARN] Length mismatch: ref={len(ref)}, dut={len(dut)}. Truncating to min.")
        n = min(len(ref), len(dut))
        ref = ref[:n]
        dut = dut[:n]

    diff = ref - dut
    abs_err = np.abs(diff)

    max_err = np.max(abs_err)
    mean_err = np.mean(abs_err)
    rms_err = np.sqrt(np.mean(abs_err**2))
    EPILSON = 1e-6

    print("[RESULT] Comparison between reference and DUT:")
    print(f"         Length          : {len(ref)} samples")
    print(f"         Max abs error   : {max_err:.6e}")
    print(f"         Mean abs error  : {mean_err:.6e}")
    print(f"         RMS error       : {rms_err:.6e}")


    if max_err > EPILSON:
        # Dump first few bins for sanity
        print("\n[DEBUG] First 8 samples (ref, dut, diff):")
        for i in range(min(8, len(ref))):
            print(
                f"  k={i:2d}: "
                f"ref={ref[i]: .6f}, "
                f"dut={dut[i]: .6f}, "
                f"diff={diff[i]: .6e}"
            )
        print("\n[ERROR] Mismatch detected between reference and DUT!")
        return
    
    print("\n[INFO] Comparison complete. Results match within tolerance.")


def main():
    parser = argparse.ArgumentParser(description="Compare two FFT .mem files (complex Q1.15).")
    parser.add_argument(
        "--ref",
        required=True,
        help="Reference .mem file (golden model).",
    )
    parser.add_argument(
        "--dut",
        required=True,
        help="DUT .mem file (hardware output).",
    )
    args = parser.parse_args()

    print(f"[INFO] Loading reference from {args.ref}")
    ref = load_mem_file(args.ref)

    print(f"[INFO] Loading DUT from {args.dut}")
    dut = load_mem_file(args.dut)

    compare_results(ref, dut)


if __name__ == "__main__":
    main()
