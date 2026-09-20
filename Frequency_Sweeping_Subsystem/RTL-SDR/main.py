"""
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           main.py
Author:         Cameron Homer
Date:           09/16/2026
Description:    Executable script for the frequency sweeping subsystem. This script will run the frequency sweeping receiver and the focused receiver in parallel.
"""

# Imports
import signal
import time
import threading
import queue
from rtlsdr import RtlSdr
from sweeping_rx import SweepingRx
from focused_rx import FocusedRx

 # Configuration
SAMPLING_SLEEP_TIME = 0.005
FOCUSED_TIME = 1.0
START_FREQ = 88e6
END_FREQ = 108e6
DEFAULT_FREQ = (START_FREQ + END_FREQ) / 2
STEP_FREQ = 2e6
SAMPLE_RATE = 2e6
GAIN = 'auto'

def main():
    # Setup signal handling
    stop_event = threading.Event()

    def signal_handler(sig, frame):
        stop_event.set()

    signal.signal(signal.SIGINT, signal_handler)

    # Setup our queue for inter-thread communication
    target_freq_queue = queue.Queue(maxsize=1)  # Maxsize is set bc the RTL is scanning at FM Broadcast frequencies and I actually want to test the capabilites of the state machine in focused_rx so I can't have an infinite queue

    # Initialize SDR
    sweeping_sdr = RtlSdr(device_index=0)
    focused_sdr = RtlSdr(device_index=1)

    # Configure SDRs (Remeber that for now the configure settings are fit for the RTL-SDR but will not be suitable for the USRP 2901)
    sweeping_sdr.sample_rate = SAMPLE_RATE
    sweeping_sdr.center_freq = START_FREQ
    sweeping_sdr.gain = GAIN
    focused_sdr.sample_rate = SAMPLE_RATE
    focused_sdr.center_freq = DEFAULT_FREQ
    focused_sdr.gain = GAIN

    # Class instantiation
    sweeping_rx = SweepingRx(sweeping_sdr, START_FREQ, END_FREQ, STEP_FREQ)
    focused_rx = FocusedRx(focused_sdr)

    # Sampling Start Up (We need threading bc we want to run both receivers in parallel)
    thread_sweeping = threading.Thread(target=sweeping_rx.sampling, args=(SAMPLING_SLEEP_TIME, stop_event, target_freq_queue))
    thread_focused = threading.Thread(target=focused_rx.sampling, args=(DEFAULT_FREQ, FOCUSED_TIME, SAMPLING_SLEEP_TIME, stop_event, target_freq_queue))
    thread_sweeping.start()
    thread_focused.start()

    while not stop_event.is_set():
        time.sleep(0.05)

    # Shutdown
    thread_sweeping.join()
    thread_focused.join()
    sweeping_rx.close()
    focused_rx.close()

if __name__ == "__main__":
    main()