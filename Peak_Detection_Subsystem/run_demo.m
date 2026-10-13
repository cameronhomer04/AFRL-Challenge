rng(0);  

fs = 2.4e6;           % 2.4 MS/s
fc = 915.0e6;         % tuned to 915 MHz
N = 2^18;

% Synthetic tone at 915.35 MHz, i.e. +350 kHz baseband offset
t = (0:N-1)' / fs;
f_true = 915.35e6;
offset = f_true - fc;

tone  = 0.25 * exp(2j * pi * offset * t);
noise = (randn(N,1) + 1j*randn(N,1)) / sqrt(2);
iq = tone + noise;

res = detect_peak(iq, fc, fs, 915.1e6, 915.6e6, 'nfft', 4096, 'threshold_db', 12.0);

fprintf('Detected:      %d\n', res.detected);
if res.detected
    err = res.peak_freq_hz - f_true;
    fprintf('Peak freq:     %.6f MHz\n', res.peak_freq_hz / 1e6);
    fprintf('True freq:     %.6f MHz\n', f_true / 1e6);
    fprintf('Error:         %.1f Hz  (bin width %.1f Hz)\n', err, res.bin_width_hz);
end
fprintf('SNR:           %.1f dB\n', res.snr_db);
fprintf('Noise floor:   %.1f dB\n', res.noise_floor_db);

plot_result(res, 'peak_detection_matlab.png', 'Band-limited peak detection');
fprintf('Wrote peak_detection_matlab.png\n');
