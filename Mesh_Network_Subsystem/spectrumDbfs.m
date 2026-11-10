function [powerDb, freqHz] = spectrumDbfs(x, sampleRate, nfft)
% SPECTRUMDBFS  Averaged power spectrum in dB relative to full scale.
%
%   [powerDb, freqHz] = spectrumDbfs(x, sampleRate, nfft)
%
%   x          - complex baseband samples
%   sampleRate - samples per second
%   nfft       - FFT length per segment (e.g. 1024)
%
%   powerDb - power per frequency bin, dBFS (a full-scale tone reads 0 dB)
%   freqHz  - frequency of each bin, -sampleRate/2 .. sampleRate/2
%
% Averages Hann-windowed segments, so the trace is smooth enough to watch live.

    x = x(:);
    numSegments = floor(numel(x) / nfft);
    if numSegments < 1
        x(end+1:nfft) = 0;
        numSegments = 1;
    end

    w = 0.5 - 0.5*cos(2*pi*(0:nfft-1).' / nfft);          % Hann window
    segments = reshape(x(1:numSegments*nfft), nfft, numSegments) .* w;
    power = mean(abs(fft(segments)).^2, 2) / sum(w)^2;

    powerDb = 10*log10(fftshift(power) + 1e-20);
    freqHz  = (-nfft/2 : nfft/2-1).' * (sampleRate / nfft);
end
