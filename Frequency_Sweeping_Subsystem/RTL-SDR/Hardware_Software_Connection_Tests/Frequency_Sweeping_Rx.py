"""
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           Frequency_Sweeping_Rx
Author:         Cameron Homer
Date:           09/16/2026
Description:    This is the outdate original script without class implementation
"""

# Imports
import time
import signal
from matplotlib import pyplot as plt
from rtlsdr import RtlSdr

# Setup signal handling
running = True

def signal_handler(sig, frame):
    global running
    running = False

signal.signal(signal.SIGINT, signal_handler)

# Configuration
SLEEP_TIME = 0.005
START_FREQ = 88e6
END_FREQ = 108e6
STEP_FREQ = 2e6
SAMPLE_RATE = 2e6
GAIN = 'auto'
POWER_THRESHOLD = 3

# Initialize SDR
sdr = RtlSdr()
sdr.sample_rate = SAMPLE_RATE
sdr.center_freq = START_FREQ
sdr.gain = GAIN

# PSD Plot Setup
plt.ion()
fig, ax = plt.subplots()

def plot_psd(samples):
    ax.clear()
    ax.psd(samples, NFFT=1024, Fs=sdr.sample_rate / 1e6, Fc=sdr.center_freq / 1e6)
    ax.set_xlabel('Frequency (MHz)')
    ax.set_ylabel('Power (dB)')
    ax.set_title('RTL-SDR Power Spectrum')
    ax.grid(True)
    fig.canvas.draw_idle()
    #plt.pause()

# Sweeping
sweeping_up = True
while running:                                                                                                                      # Want constant sweeping for now
    # Sample at center frequency
    samples = sdr.read_samples(256 * 1024)
    time.sleep(SLEEP_TIME)

    plot_psd(samples)

    fig.canvas.draw_idle()
    plt.pause(0.05)
    
    # Increase or decrease center frequency for next scan
    if(sweeping_up):                                                                                                                # Want to increase frequency if we've not reached the max and are sweeping up
        sdr.center_freq += STEP_FREQ
    else:                                                                                                                           # Want to decrease frequency if we've not reached the min and are sweeping down
        sdr.center_freq -= STEP_FREQ

    # Check if we need to change direction
    if(sdr.center_freq >= END_FREQ):
        sweeping_up = False
    elif(sdr.center_freq <= START_FREQ):
        sweeping_up = True
    
sdr.close()