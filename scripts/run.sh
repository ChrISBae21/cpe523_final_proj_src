#!/bin/bash
set -euo pipefail

N=1024
SIGNAL="sine"
K=16

# 1) Generate twiddle ROM
python3 twiddle_gen.py --N "$N" --frac_bits 15 --outfile twiddle_rom.mem
mv twiddle_rom.mem ../mem/twiddle_rom.mem

# 2) Generate time-domain test signal in Q1.15
python3 mem_time_gen.py \
  --pattern "$SIGNAL" \
  --N "$N" \
  --k "$K" \
  --out "${SIGNAL}_time.mem"

cp "${SIGNAL}_time.mem" "../mem/${SIGNAL}_time.mem"

# # 3) Visualize time-domain signal (optional sanity check)
python3 fft_visualize.py \
  --mem_file "${SIGNAL}_time.mem" \
  --title "${SIGNAL} Signal in Time Domain"

# # 4) Run reference FFT in Python (golden model)
python3 fft_sim.py \
  --in_mem "${SIGNAL}_time.mem" \
  --out_ref_mem "${SIGNAL}_freq.mem" \
  --N "$N"

# # 5) Visualize frequency-domain result (bit-reversed + half spectrum)
python3 fft_visualize.py \
  --mem_file "${SIGNAL}_freq.mem" \
  --title "FFT of ${SIGNAL} Signal" \
  --half \
  --bitrev

# Compare
# python fft_check.py --ref sine_freq.mem --dut ../fft_accel_vivado/fft_accel_vivado.sim/sim_1/behav/xsim/fft_output.mem