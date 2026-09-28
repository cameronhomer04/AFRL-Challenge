%{
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           sweeping_rx.m
Author:         Cameron Homer
Date:           09/25/2026
Description:    Helper function that handles the SWEEPING State
%}

function [focusFreq, sweepingUp] = sweeping_rx(USRP, sweepingUp, MIN_FREQ, MAX_FREQ, STEP_FREQ, SAMPLE_RATE, POWER_THRESHOLD)

arguments (Input)
    USRP
    sweepingUp
    MIN_FREQ
    MAX_FREQ
    STEP_FREQ
    SAMPLE_RATE
    POWER_THRESHOLD
end

arguments (Output)
    focusFreq
    sweepingUp
end

% Generate I/Q data to stream to peak detection program
[iqdata, ~, ~] = USRP();
focusFreq = rudimentary_peak_detection(iqdata, USRP.CenterFrequency, SAMPLE_RATE, POWER_THRESHOLD);
if isnan(focusFreq)
    if sweepingUp
        nextFreq = USRP.CenterFrequency + STEP_FREQ;
        if nextFreq >= MAX_FREQ
            nextFreq = MAX_FREQ;
            sweepingUp = false;
        end
    else
        nextFreq = USRP.CenterFrequency - STEP_FREQ;
        if nextFreq <= MIN_FREQ
            nextFreq = MIN_FREQ;
            sweepingUp = true;
        end
    end
    USRP.CenterFrequency = nextFreq;
    USRP();
end
end