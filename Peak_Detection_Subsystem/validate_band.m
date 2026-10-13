function validate_band(fc, fs, f_low, f_high)
% VALIDATE_BAND  Raise an error if [f_low, f_high] is not inside fc +/- fs/2.
% Port of Step 2 from peak_detect.py (validate_band).

    if f_low >= f_high
        error('validate_band:badRange', ...
            'f_low (%g) must be below f_high (%g)', f_low, f_high);
    end

    win_low  = fc - fs / 2;
    win_high = fc + fs / 2;

    if f_low < win_low || f_high > win_high
        error('validate_band:outsideWindow', ...
            ['Search band [%.3f, %.3f] MHz falls outside the observable ' ...
             'window [%.3f, %.3f] MHz. Retune fc or increase fs.'], ...
            f_low/1e6, f_high/1e6, win_low/1e6, win_high/1e6);
    end
end
