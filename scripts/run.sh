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

# 3) Make golden output using reference model
python fft_compute.py \
  --in_mem "${SIGNAL}_time.mem" \
  --out_ref_mem "${SIGNAL}_freq_dit.mem" \
  --n "$N"

python fft_real_compute.py \
  --in_mem "${SIGNAL}_time.mem" \
  --out_mem "${SIGNAL}_freq_np.mem" \
  --n "$N"

# 4) Visualize frequency-domain result (bit-reversed + half spectrum)
python3 fft_comp_vis.py \
  --time_mem "${SIGNAL}_time.mem" \
  --title "FFT of ${SIGNAL} Signal"


# Compare
# python fft_check.py --ref sine_freq.mem --dut ../fft_accel_vivado/fft_accel_vivado.sim/sim_1/behav/xsim/fft_output.mem