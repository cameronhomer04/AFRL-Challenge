function result = run_capture(matFile, varargin)
    p = inputParser;
    addParameter(p, 'f_low', []);
    addParameter(p, 'f_high', []);
    addParameter(p, 'min_duty', 0.5);
    addParameter(p, 'threshold_db', 12.0);
    addParameter(p, 'nfft', 4096);
    addParameter(p, 'out', 'capture_peak_detection.png');
    parse(p, varargin{:});
    opt = p.Results;

    % ---- Load the capture --------------------------------------------
    s = load(matFile, 'iq', 'fc', 'fs');
    iq = s.iq;
    fc = s.fc;
    fs = s.fs;

    fprintf('Loaded %s: %d samples, fc=%.4f GHz, fs=%.2f MS/s\n', ...
        matFile, numel(iq), fc/1e9, fs/1e6);

    % ---- Default search band: just inside the Nyquist edges ----------
    margin = fs * 0.0005;
    if isempty(opt.f_low)
        f_low = fc - fs/2 + margin;
    else
        f_low = opt.f_low;
    end
    if isempty(opt.f_high)
        f_high = fc + fs/2 - margin;
    else
        f_high = opt.f_high;
    end

    % ---- Run the detector ----------------------------------------------
    result = detect_peak(iq, fc, fs, f_low, f_high, ...
        'nfft', opt.nfft, ...
        'threshold_db', opt.threshold_db, ...
        'min_duty', opt.min_duty);

    % ---- Report ----------------------------------------------------
    fprintf('Detected:      %d\n', result.detected);
    if result.detected
        fprintf('Peak freq:     %.6f MHz\n', result.peak_freq_hz / 1e6);
        fprintf('Duty at peak:  %.2f\n', result.duty_at_peak);
    else
        fprintf('Interference flag: %d  (naive peak would have been %.4f MHz)\n', ...
            result.interference_flag, result.naive_peak_freq_hz / 1e6);
    end
    fprintf('SNR:           %.1f dB\n', result.snr_db);
    fprintf('Noise floor:   %.1f dB\n', result.noise_floor_db);

    % ---- Plot --------------------------------------------------------
    [~, baseName] = fileparts(matFile);
    plot_result(result, opt.out, sprintf('Capture: %s', baseName));
    fprintf('Wrote %s\n', opt.out);
end
