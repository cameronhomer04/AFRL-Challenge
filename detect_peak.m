function result = detect_peak(iq, fc, fs, f_low, f_high, varargin)
% Detect the strongest persistent spectral peak in [f_low, f_high].

    p = inputParser;
    addParameter(p, 'nfft', 4096);
    addParameter(p, 'overlap', 0.5);
    addParameter(p, 'threshold_db', 12.0);
    addParameter(p, 'dc_guard_bins', 3);
    addParameter(p, 'min_duty', 0.5);
    parse(p, varargin{:});
    opt = p.Results;

    validate_band(fc, fs, f_low, f_high);

    [f_abs, t, Sxx] = compute_spectrogram(iq, fc, fs, opt.nfft, opt.overlap);

    % Per-frame spectrogram in dB -- needed by the persistence filter and
    % reused by plot_result.
    Sxx_db = 10 * log10(Sxx + 1e-20);

    % Step 5: average LINEAR power across frames, then convert to dB.
    psd_lin = mean(Sxx, 2);
    psd_db  = 10 * log10(psd_lin + 1e-20);

    % Step 6: restrict to the search band
    band_mask = (f_abs >= f_low) & (f_abs <= f_high);
    if ~any(band_mask)
        error('detect_peak:emptyBand', ...
            'Search band contains no FFT bins; increase nfft.');
    end

    % Notch the DC/LO-leakage spike at fc if it falls inside the band
    [~, dc_idx] = min(abs(f_abs - fc));
    lo = max(1, dc_idx - opt.dc_guard_bins);
    hi = min(numel(f_abs), dc_idx + opt.dc_guard_bins);
    band_mask(lo:hi) = false;

    band_idx    = find(band_mask);
    band_psd_db = psd_db(band_idx);

    % Step 7: robust noise floor (median ignores the carrier; mean would not)
    noise_floor_db = median(band_psd_db);
    threshold = noise_floor_db + opt.threshold_db;

    % Strongest bin of the time-averaged PSD -- what a naive detector
    % (no interference rejection) would have returned.
    [~, naive_local] = max(band_psd_db);
    naive_k = band_idx(naive_local);

    % Step 8a: persistence (duty-cycle) filter ---------------------------
    band_db_frames = Sxx_db(band_idx, :);            % (bins x frames)

    % Noise floor re-estimated per frame so a wideband burst doesn't
    % distort the threshold used on the other frames.
    frame_floor_db = median(band_db_frames, 1);       % (1 x frames)

    hits = band_db_frames > (frame_floor_db + opt.threshold_db);  % (bins x frames)
    duty = mean(hits, 2);                              % (bins x 1)

    if opt.min_duty > 0
        persistent_bins = duty >= opt.min_duty;
    else
        persistent_bins = band_psd_db >= threshold;
    end

    % Step 8b: choose the strongest bin among those that passed
    if any(persistent_bins)
        candidate_psd = band_psd_db;
        candidate_psd(~persistent_bins) = -Inf;
        [~, local_k] = max(candidate_psd);
        global_k = band_idx(local_k);
        detected = true;
    else
        global_k = naive_k;
        detected = false;
    end

    peak_power_db = psd_db(global_k);
    duty_at_peak  = duty(band_idx == global_k);
    duty_at_peak  = duty_at_peak(1);

    % Flag interference: loudest bin was strong enough for a naive
    % detector, but the persistence filter rejected it as bursty.
    interference_flag = (opt.min_duty > 0) && ...
        (band_psd_db(naive_local) >= threshold) && ...
        ~persistent_bins(naive_local);

    % Step 9: sub-bin refinement
    peak_freq       = parabolic_refine(f_abs, psd_db, global_k);
    naive_peak_freq = parabolic_refine(f_abs, psd_db, naive_k);

    result = struct();
    result.detected = detected;
    if detected
        result.peak_freq_hz = peak_freq;
    else
        result.peak_freq_hz = [];
    end
    result.peak_power_db       = peak_power_db;
    result.noise_floor_db      = noise_floor_db;
    result.snr_db              = peak_power_db - noise_floor_db;
    result.threshold_db        = threshold;
    result.bin_width_hz        = f_abs(2) - f_abs(1);
    result.duty_at_peak        = duty_at_peak;
    result.interference_flag   = interference_flag;
    result.naive_peak_freq_hz  = naive_peak_freq;
    result.naive_peak_power_db = psd_db(naive_k);

    % Retained for plot_result
    result.f_abs  = f_abs;
    result.t      = t;
    result.Sxx_db = Sxx_db;
    result.psd_db = psd_db;
    result.f_low  = f_low;
    result.f_high = f_high;
end
