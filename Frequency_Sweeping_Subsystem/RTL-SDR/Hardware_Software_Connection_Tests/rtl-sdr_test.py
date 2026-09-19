"""
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           RTL-SDR_Test
Author:         Cameron Homer
Date:           09/16/2026
Description:    This script is a test script for the RTL-SDR. The purpose of which is to test the hardware is working properly
"""

import matplotlib.pyplot as plt
import numpy as np
from rtlsdr import RtlSdr

# Initialize SDR
sdr = RtlSdr()
sdr.sample_rate = 2.048e6 # Hz
sdr.center_freq = 100e6   # Hz
sdr.freq_correction = 60  # PPM
sdr.gain = 'auto'

samples = sdr.read_samples(256 * 1024)
sdr.close()

# Plot the Power Spectral Density (PSD)
plt.figure(figsize=(10, 6))
plt.psd(samples, NFFT=1024, Fs=sdr.sample_rate / 1e6, Fc=sdr.center_freq / 1e6)
plt.xlabel('Frequency (MHz)')
plt.ylabel('Power (dB)')
plt.title('RTL-SDR Power Spectrum')
plt.grid(True)
plt.show()