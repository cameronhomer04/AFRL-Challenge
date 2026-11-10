function keepRunning = updateLiveRxDisplay(d, cfg, block, rx, metricHistory, statusLines)
% UPDATELIVERXDISPLAY  Refresh the live receiver window with the latest block.
%
%   keepRunning = updateLiveRxDisplay(d, cfg, block, rx, metricHistory, statusLines)
%
%   d             - handles from createLiveRxDisplay
%   block         - samples captured in this block
%   rx            - result of receivePacket for this block
%   metricHistory - preamble metric of every block so far
%   statusLines   - cell array of text lines shown above the plots
%
%   keepRunning - false once Stop is pressed or the window is closed

    keepRunning = isgraphics(d.fig) && ~d.stopButton.Value;
    if ~keepRunning
        return;
    end

    fs = cfg.sampleRate;

    [powerDb, freqHz] = spectrumDbfs(block, fs, 1024);
    set(d.hSpectrum, "XData", freqHz/1e3, "YData", powerDb);

    n = min(2000, numel(block));
    t = (0:n-1).' / fs * 1e3;
    set(d.hI, "XData", t, "YData", real(block(1:n)));
    set(d.hQ, "XData", t, "YData", imag(block(1:n)));
    xlim(d.axIQ, [0, max(t(end), eps)]);

    % Keep the last decoded packet on screen until a new one arrives.
    if rx.valid && ~isempty(rx.payloadDiff)
        set(d.hConstellation, "XData", real(rx.payloadDiff), "YData", imag(rx.payloadDiff));
    end

    shown = max(1, numel(metricHistory) - 199) : numel(metricHistory);   % last 200 blocks
    set(d.hMetric, "XData", shown, "YData", metricHistory(shown));
    xlim(d.axMetric, [shown(1), max(shown(end), shown(1) + 1)]);

    d.layout.Title.String = statusLines;
    drawnow limitrate;
end
