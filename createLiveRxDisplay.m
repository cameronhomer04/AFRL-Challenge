function d = createLiveRxDisplay(cfg)
% CREATELIVERXDISPLAY  Open the live receiver window used by runReceiverLoop.
%
%   d = createLiveRxDisplay(cfg)
%
%   d - struct of graphics handles; pass it to updateLiveRxDisplay.
%
% Panels: received spectrum, received I/Q samples, decision constellation of
% the last decoded packet, and the preamble-detection metric over time.
% The Stop button (or closing the window) ends the continuous run.

    fs = cfg.sampleRate;

    d.fig = figure("Name", "Live DQPSK Receiver", "NumberTitle", "off");
    d.layout = tiledlayout(d.fig, 2, 2, "TileSpacing", "compact", "Padding", "compact");
    d.layout.Title.String = "Starting receiver...";
    d.layout.Title.FontSize = 10;

    % ---- Spectrum ----
    ax = nexttile(d.layout);
    d.hSpectrum = plot(ax, NaN, NaN);
    grid(ax, "on");
    xlim(ax, [-fs/2, fs/2] / 1e3);
    ylim(ax, [-120, 0]);
    xlabel(ax, "Frequency offset from centre (kHz)");
    ylabel(ax, "Power (dBFS per bin)");
    title(ax, "Received spectrum");

    % ---- I/Q samples ----
    ax = nexttile(d.layout);
    d.hI = plot(ax, NaN, NaN);
    hold(ax, "on");
    d.hQ = plot(ax, NaN, NaN);
    grid(ax, "on");
    ylim(ax, [-1, 1]);                         % +-1 is full scale: clipping shows here
    xlabel(ax, "Time (ms)");
    ylabel(ax, "Amplitude");
    legend(ax, "I", "Q", "Location", "northeast");
    title(ax, "Received I/Q samples (full scale = \pm1)");
    d.axIQ = ax;

    % ---- Decision constellation ----
    ax = nexttile(d.layout);
    d.hConstellation = plot(ax, NaN, NaN, "o");
    hold(ax, "on");
    ideal = exp(1j * (pi/4 + (0:3)*(pi/2)));
    plot(ax, real(ideal), imag(ideal), "rx", "MarkerSize", 12, "LineWidth", 2);
    grid(ax, "on");
    axis(ax, "equal");
    xlim(ax, [-1.6, 1.6]);
    ylim(ax, [-1.6, 1.6]);
    xlabel(ax, "Differential I");
    ylabel(ax, "Differential Q");
    title(ax, "Decision constellation (last decoded packet)");

    % ---- Detection metric history ----
    ax = nexttile(d.layout);
    d.hMetric = plot(ax, NaN, NaN, ".-");
    hold(ax, "on");
    yline(ax, cfg.minPreambleMetric, "r--", "Detection threshold");
    grid(ax, "on");
    ylim(ax, [0, 1.05]);
    xlabel(ax, "Block number");
    ylabel(ax, "Preamble metric");
    title(ax, "Packet detection (1 = perfect match)");
    d.axMetric = ax;

    % ---- Stop button ----
    d.stopButton = uicontrol(d.fig, "Style", "togglebutton", "String", "Stop", ...
        "Units", "normalized", "Position", [0.90, 0.95, 0.08, 0.045], ...
        "FontWeight", "bold");

    drawnow;
end
