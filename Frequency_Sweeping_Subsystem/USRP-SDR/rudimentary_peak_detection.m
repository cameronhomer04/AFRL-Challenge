%{
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           focused_rx.m
Author:         Cameron Homer
Date:           09/25/2026
Description:    Rudimentary Peak Detection module for testing purposes only
%}

function [peakFreq] = rudimentary_peak_detection(iqdata, centerFreq, SAMPLE_RATE, POWER_THRESHOLD)

arguments (Input)
    iqdata
    centerFreq
    SAMPLE_RATE
    POWER_THRESHOLD
end

arguments (Output)
    peakFreq
end

N = length(iqdata);
spectrum = abs(fftshift(fft(iqdata)));
[peakVal, peakIndex] = max(spectrum);
if peakVal >= POWER_THRESHOLD
    freqVector = (-N/2 : (N/2)-1) * (SAMPLE_RATE / N);
    peakOffset = freqVector(peakIndex);
    peakFreq = centerFreq + peakOffset;
    peakFreq = NaN;
else
    peakFreq = NaN;
end