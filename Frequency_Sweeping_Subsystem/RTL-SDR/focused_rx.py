"""
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           focused_rx.py
Author:         Cameron Homer
Date:           09/16/2026
Description:    Class implementation of the focused receiver
"""

# Imports
import time

# Class definition for the focused receiver
class FocusedRx:
    # Initialization for FocusedRx class
    def __init__(self, sdr_device):
        self.sdr = sdr_device

    # Destructor for FocusedRx class
    def close(self):
        self.sdr.close()

    # Sample at center frequency
    def sampling(self, sleep_time, stop_event):
        while not stop_event.is_set():
            samples = self.sdr.read_samples(256 * 1024)
            time.sleep(sleep_time)
    