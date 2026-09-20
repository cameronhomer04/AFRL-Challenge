"""
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           rudimentary_peak_detection.py
Author:         Cameron Homer
Date:           09/16/2026
Description:    Rudimentary peak detection implementation for subsystem testing. Actually peak detection is handled by another group member
"""

# Imports
import numpy as np

def rudimentary_peak_detection(samples, center_freq, sample_rate, threshold):
    # Convert I/Q samples to power information
    fft_samples = np.fft.fftshift(np.fft.fft(samples))
    power_spectrum = 10 * np.log10(np.abs(fft_samples) ** 2)

    # Convert I/Q samples to frequency information
    frequencies = np.fft.fftshift(np.fft.fftfreq(len(samples), d=1/sample_rate)) + center_freq

    # Find highest peak in the power spectrum
    peak_index = np.argmax(power_spectrum)

    # Check if the peak exceeds the threshold
    if power_spectrum[peak_index] > threshold:
        peak_freq = frequencies[peak_index]
        return peak_freq
    else:
        return None

"""
This is a very basic peak detection system 
(literally just finds highest peak and compares if it is above a threshold).
This is NOT meant to be a good peak detection system (although maybe by some miracle it is). 
It is simply something to test if the sweeping receiver can communicate with the focused receiver 
"""