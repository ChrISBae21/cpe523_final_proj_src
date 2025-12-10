import numpy as np

N = 1024
k = np.arange(N // 2)
W = np.exp(-2j * np.pi * k / N)   # e^{-j2πk/N}

scale = 2 ** 15
Wr = np.round(np.real(W) * scale).astype(int)
Wi = np.round(np.imag(W) * scale).astype(int)

def to_16bit(x):
    x = np.where(x < 0, x + 2 ** 16, x)  # 2's complement
    return x & 0xFFFF

Wr16 = to_16bit(Wr)
Wi16 = to_16bit(Wi)

with open("twiddle_1024.mem", "w") as f:
    for r, i in zip(Wr16, Wi16):
        word = (r << 16) | i
        f.write(f"{word:08X}\n")
