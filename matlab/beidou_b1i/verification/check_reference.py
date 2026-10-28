"""Independent numeric checks; does NOT execute or certify MATLAB code.
Requires numpy/scipy. Does not produce deliverable radio recordings.
"""
import json
import math
from pathlib import Path
import numpy as np
from scipy.signal import lfilter


def bch_integer(message):
    word = message << 4
    remainder = word
    for bit in range(14, 3, -1):
        if remainder & (1 << bit):
            remainder ^= 0b10011 << (bit - 4)
    return word | remainder


def verify():
    words = [bch_integer(m) for m in range(2048)]
    assert min(w.bit_count() for w in words[1:]) == 3
    assert len(set(words)) == 2048
    assert all(w >> 4 == i for i, w in enumerate(words))
    # Stage-number convention independently represented as integer LFSRs.
    g1 = g2 = int('01010101010', 2)
    bits = []
    for _ in range(2046):
        # PRN12 uses ICD stage 3 xor stage 6, integer bits 8 and 5.
        bits.append((g1 ^ (g2 >> 8) ^ (g2 >> 5)) & 1)
        f1 = sum((g1 >> j) & 1 for j in [0, 1, 2, 3, 4, 10]) % 2
        f2 = sum((g2 >> j) & 1 for j in [0, 2, 3, 6, 7, 8, 9, 10]) % 2
        g1 = (g1 >> 1) | (f1 << 10)
        g2 = (g2 >> 1) | (f2 << 10)
    assert ''.join(map(str, bits[:64])) == (
        '1010010010000111010000110010101101011001100111001011100001110010')
    assert sum(bits) == 1024
    # Distinct payload capacities from the independent ICD word definitions.
    assert 26 + 9 * 22 == 224
    assert 15 + 15 + 9 * 30 == 300
    # Filter + thermal-noise calibration, and streaming equals convolution.
    fs, cutoff, length = 8.184e6, 2.8e6, 65
    ix = np.arange(length) - (length - 1) / 2
    h = 2 * cutoff / fs * np.sinc(2 * cutoff / fs * ix) * np.hamming(length)
    h /= h.sum()
    enbw = fs * np.dot(h, h)
    c = 10 ** (-158 / 10)
    n0 = c / 10 ** (45 / 10)
    rng = np.random.default_rng(20261023)
    n = 1_000_000
    noise = np.sqrt(n0 * fs / 2) * (rng.normal(size=n) + 1j * rng.normal(size=n))
    output = lfilter(h, [1], noise)[length:]
    power = float(np.mean(abs(output) ** 2))
    assert abs(power / (n0 * enbw) - 1) < 0.01
    # Approximate B1I filtering loss with four samples/chip and a code period.
    base = np.tile(np.repeat(1 - 2 * np.array(bits), 4), 30)
    clean = lfilter(h, [1], base)[length:]
    loss = 10 * math.log10(float(np.mean(clean ** 2)))
    assert -2 < loss <= 0.01
    # Doppler/code rate relation (a 1000 m/s receding satellite).
    c_light, carrier, chiprate = 299792458.0, 1561.098e6, 2.046e6
    fd = -carrier * 1000 / c_light
    code_delta = -chiprate * 1000 / c_light
    assert abs(code_delta / fd - chiprate / carrier) < 1e-15
    result = {
        'status': 'PASS: independent numerical/reference checks only',
        'matlab_executed': False,
        'bch_codewords_checked': len(words), 'bch_minimum_distance': 3,
        'prn12_ones': sum(bits), 'equivalent_noise_bandwidth_Hz': enbw,
        'noise_power_relative_error': power / (n0 * enbw) - 1,
        'approximate_filter_signal_loss_dB': loss,
        'default_60s_complex_samples': int(fs * 60),
        'default_60s_waveform_bytes': int(fs * 60 * 8),
    }
    print(json.dumps(result, indent=2))
    return result


if __name__ == '__main__':
    result = verify()
    Path(__file__).with_name('reference_results.json').write_text(
        json.dumps(result, indent=2) + '\n', encoding='utf-8')
