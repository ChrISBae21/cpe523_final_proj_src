Pictures
 - sine_freq_np_mag.png
    - using numpy to calc FFT
    - clean graph of what it should look like
 - sine_freq_dit_mag.png
    - papers algo
    - correct results just looks weird
    - kinda looks inverted, valleys where peaks should be (IDK what this means)
 - fft_output_mag.png
    - same as dit just half since mirrored

Results
 - fft_real_compute.py
    - uses floats to compute fft
 - fft_compute.py
    - implemented the papers algo
 - compared the output results and matched

Improvements
 - why is the fft visual so noisy?
    - this is an approx algo
    - q1.15 only has so much precision
 - how could I fix them?
    - add per-stage scaling the bfu result to stop it from overflowing
    - increase the internal bit width in the bfu to prevent overflowing
    - maybe with more samples could improve? (idk actually)

How to run
 - run scripts/run.sh to make the mem files

