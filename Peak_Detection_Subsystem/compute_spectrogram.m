function [f_abs, t, Sxx] = compute_spectrogram(iq, fc, fs, nfft, overlap)
% STFT of complex I/Q data, frequency axis in absolute RF.

    if nargin < 5 || isempty(overlap)
        overlap = 0.5;
    end

    nperseg  = nfft;
    noverlap = floor(nperseg * overlap);

    iq = iq(:);  % ensure column vector, as spectrogram expects

    [~, f_base, t, Sxx] = spectrogram( ...
        iq, ...
        hann(nperseg, 'periodic'), ...
        noverlap, ...
        nfft, ...
        fs, ...
        'psd');

    % Re-map bins at/above fs/2 to their negative-frequency equivalent,
    % then sort ascending -- the manual equivalent of np.fft.fftshift.
    f_base = f_base(:);
    f_base(f_base >= fs/2) = f_base(f_base >= fs/2) - fs;
    [f_base, order] = sort(f_base);
    Sxx = Sxx(order, :);

    f_abs = fc + f_base;      % column vector, ascending, absolute RF Hz
    t = t(:)';                 % row vector, seconds
end
