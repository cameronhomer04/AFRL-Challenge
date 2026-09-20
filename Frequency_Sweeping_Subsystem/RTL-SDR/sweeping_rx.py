"""
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           sweeping_rx.py
Author:         Cameron Homer
Date:           09/16/2026
Description:    Class implementation of the frequency sweeping receiver
"""

# Imports
import queue
import time
from rudimentary_peak_detection import rudimentary_peak_detection

# Temporary power threshold (dB) for rudimentary peak detection
POWER_THRESHOLD = -1

# Class definition for the frequency sweeping receiver
class SweepingRx:
    # Initialization for SweepingRx class
    def __init__(self, sdr_device, start_freq, end_freq, step_freq):
        self.sdr = sdr_device
        self.start_freq = start_freq
        self.end_freq = end_freq
        self.step_freq = step_freq

    # Destructor for SweepingRx class
    def close(self):
        self.sdr.close()

    # Sample at center frequency
    def sampling(self, sleep_time, stop_event, target_freq_queue):
        sweeping_up = True
        while not stop_event.is_set():
            # Sample at center frequency
            samples = self.sdr.read_samples(256 * 1024)
            time.sleep(sleep_time)

            # Peak detection (rudimentary implementation)
            detect_freq = rudimentary_peak_detection(samples, self.sdr.center_freq, self.sdr.sample_rate, POWER_THRESHOLD)

            # Add to frequency detection queue
            if detect_freq is not None:
                try:
                    #print(f"[SweepingRx]:\nDetected peak frequency: {detect_freq/1e6:.2f} MHz\n")
                    target_freq_queue.put_nowait(detect_freq)
                except queue.Full:
                    pass

            # Increase or decrease center frequency for next scan
            if(sweeping_up):
                self.sdr.center_freq += self.step_freq
            else:
                self.sdr.center_freq -= self.step_freq
            
            # Check if we need to change direction
            if(self.sdr.center_freq >= self.end_freq):
                sweeping_up = False
            elif(self.sdr.center_freq <= self.start_freq):
                sweeping_up = True