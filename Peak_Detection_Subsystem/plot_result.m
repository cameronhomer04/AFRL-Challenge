function plot_result(result, outpath, titleStr)
% Spectrogram with the search band and detected peak marked.

    if nargin < 2 || isempty(outpath)
        outpath = 'peak_detection.png';
    end
    if nargin < 3 || isempty(titleStr)
        titleStr = 'Spectrogram';
    end

    f_abs  = result.f_abs / 1e6;   % MHz
    t      = result.t;
    Sxx_db = result.Sxx_db;
    psd_db = result.psd_db;
    f_low  = result.f_low / 1e6;
    f_high = result.f_high / 1e6;

    fig = figure('Visible', 'off', 'Position', [100 100 1400 500]);

    % ---- Left panel: spectrogram -----------------------------------
    ax1 = subplot(1, 2, 1);
    sortedVals = sort(Sxx_db(:));
    pIdx = min(max(ceil(0.995 * numel(sortedVals)), 1), numel(sortedVals));
    vmax = sortedVals(pIdx);
    vmin = vmax - 60;

    imagesc(ax1, t * 1e3, f_abs, Sxx_db, [vmin vmax]);
    set(ax1, 'YDir', 'normal');
    colormap(ax1, parula);   

    cb = colorbar(ax1);
    ylabel(cb, 'Power (dB)');

    hold(ax1, 'on');
    yline(ax1, f_low,  'w--', 'LineWidth', 1);
    yline(ax1, f_high, 'w--', 'LineWidth', 1);
    if result.detected
        fpk = result.peak_freq_hz / 1e6;
        yline(ax1, fpk, 'r-', 'LineWidth', 1.2);
    end
    if result.interference_flag
        fbad = result.naive_peak_freq_hz / 1e6;
        yline(ax1, fbad, ':', 'Color', [1 0.55 0], 'LineWidth', 1.4);
    end
    hold(ax1, 'off');

    xlabel(ax1, 'Time (ms)');
    ylabel(ax1, 'Frequency (MHz)');
    title(ax1, titleStr);

    % ---- Right panel: time-averaged PSD -----------------------------
    ax2 = subplot(1, 2, 2);
    plot(ax2, psd_db, f_abs, 'Color', [0.2 0.2 0.2], 'LineWidth', 0.8);
    hold(ax2, 'on');

    % Search band shading
    yBand = [f_low f_high];
    xLims = xlim(ax2);
    patch(ax2, [xLims(1) xLims(2) xLims(2) xLims(1)], ...
               [yBand(1) yBand(1) yBand(2) yBand(2)], ...
               [0.3 0.5 1], 'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
               'DisplayName', 'Search band');

    xline(ax2, result.threshold_db, '--', 'Color', [1 0.5 0], ...
        'LineWidth', 1, 'DisplayName', 'Threshold');
    xline(ax2, result.noise_floor_db, ':', 'Color', [0 0.6 0], ...
        'LineWidth', 1, 'DisplayName', 'Noise floor');

    legendEntries = {};
    if result.detected
        fpk = result.peak_freq_hz / 1e6;
        plot(ax2, result.peak_power_db, fpk, 'rv', 'MarkerSize', 9, ...
            'MarkerFaceColor', 'r', 'DisplayName', ...
            sprintf('Peak %.4f MHz', fpk));
    end
    if result.interference_flag
        fbad = result.naive_peak_freq_hz / 1e6;
        plot(ax2, result.naive_peak_power_db, fbad, 'kx', ...
            'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', ...
            sprintf('Rejected burst %.4f MHz', fbad));
    end

    hold(ax2, 'off');
    ylim(ax2, [f_abs(1) f_abs(end)]);
    xlabel(ax2, 'Power (dB)');
    title(ax2, 'Time-averaged PSD');
    legend(ax2, 'show', 'Location', 'northwest', 'FontSize', 8);

    sgtitle(fig, '');  % keep layout clean; per-axes titles already set
    exportgraphics(fig, outpath, 'Resolution', 140);
    close(fig);
end
