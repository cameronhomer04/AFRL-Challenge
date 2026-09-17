"""
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           Frequency_Sweeping_Rx
Author:         Cameron Homer
Date:           09/16/2026
"""

# Imports
import time
import signal
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

sdr_old_freq = START_FREQ
# Sweeping
while running:                                                                                                                      # Want constant sweeping for now
    # Sample at center frequency
    print(f"Sampling at: {sdr.center_freq}")
    samples = sdr.read_samples(256 * 1024)
    time.sleep(SLEEP_TIME)
    

    # Increase or decrease center frequency for next scan
    if((sdr.center_freq < END_FREQ and sdr.center_freq > sdr_old_freq) or (sdr.center_freq == START_FREQ)):                         # Want to increase frequency if we've not reached the max and are sweeping up
        sdr_old_freq = sdr.center_freq
        sdr.center_freq += STEP_FREQ
        print(f"Increasing to: {sdr.center_freq}")
    elif(sdr.center_freq > START_FREQ):                                                                                             # Want to decrease frequency if we've not reached the min and are sweeping down
        sdr_old_freq = sdr.center_freq
        sdr.center_freq -= STEP_FREQ
        print(f"Decreasing to: {sdr.center_freq}")
        
sdr.close()