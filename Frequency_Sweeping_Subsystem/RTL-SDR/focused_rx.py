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
import queue

# Class definition for the focused receiver
class FocusedRx:
    # Initialization for FocusedRx class
    def __init__(self, sdr_device):
        self.state = "DEFAULT"
        self.start_time = None
        self.sdr = sdr_device

    # Destructor for FocusedRx class
    def close(self):
        self.sdr.close()

    # Sample at center frequency
    def sampling(self, default_freq, focused_time, sleep_time, stop_event, target_freq_queue):
        while not stop_event.is_set():
            # When in default mode, ensure no peak frequency has been detected by the sweeping receiver
            if self.state == "DEFAULT":
                # Determine if a peak frequency has been detected by the sweeping receiver
                try:
                    target_freq = target_freq_queue.get_nowait()
                    self.sdr.center_freq = target_freq
                    self.state = "FOCUSED"
                    self.start_time = time.monotonic()
                    #print(f"[FocusedRx]:\nEntering FOCUSED mode at: {target_freq/1e6:.2f} MHz\n")
                except queue.Empty:
                    pass

            # If not in default mode, we want some number of iterations before returning to default
            elif self.state == "FOCUSED":
                if time.monotonic() - self.start_time > focused_time:
                    self.sdr.center_freq = default_freq
                    self.state = "DEFAULT"
                    #print(f"[FocusedRx]:\nReturning to DEFAULT mode at: {default_freq/1e6:.2f} MHz\n")

            # Sample at center frequency (either default or detected peak)
            samples = self.sdr.read_samples(256 * 1024)
            time.sleep(sleep_time)