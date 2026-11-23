function fig = fhRepeaterSummary(stats, fh)
% FHREPEATERSUMMARY  One figure summing up a repeater run (fhRunRepeater).
%
%   fig = fhRepeaterSummary(stats, fh)
%
%   stats - returned by fhRunRepeater (runNode_FH keeps it as rpStats)
%   fh    - struct from fhConfig (channel frequencies for the labels)
%
% Three panels on a shared time axis (seconds since the radio started):
%   1. What this node did: every burst it heard and what it decided
%      (not mine / forwarded / delivered), plus the alerts it raised.
%      Labels give the next SDR or the delivered message.
%   2. Its own bursts: the channel of every slot it transmitted.
%   3. Packets received per second, good and failed checksum.
% Grey bands mark the time this node was transmitting: it hears nothing then.
%
% Called by runNode_FH at the end of a "repeater" run when showPlots is
% true. To redraw later:  fhRepeaterSummary(rpStats, fh)

    L = stats.eventLog;
    tEnd = max([stats.duration; L.time(:); 1]);
    bursts = stats.bursts;

    col.ignored   = [0.55 0.55 0.55];
    col.forwarded = [0.00 0.45 0.74];
    col.originated= [0.47 0.67 0.19];
    col.delivered = [0.85 0.33 0.10];
    col.problem   = [0.64 0.08 0.18];
    col.good      = [0.00 0.45 0.74];
    col.bad       = [0.85 0.33 0.10];
    col.tx        = [0.90 0.90 0.90];

    fig = figure('Name', sprintf('Repeater SDR %d summary', stats.myId), ...
                 'NumberTitle', 'off', 'Color', 'w', 'Position', [100 100 1000 720]);

    % ---------------- 1. Events ----------------
    ax1 = subplot(3, 1, 1); hold(ax1, 'on');
    rows = {'Problem', 'Heard, not mine', 'Forwarded', 'Originated', 'Delivered here'};
    shadeTx(ax1, bursts, [0.5 5.5], col.tx);
    for i = 1:numel(L.time)
        ev = L.event{i};
        switch ev
            case 'ignored',    y = 2; c = col.ignored;    lbl = forText(L.routeIn{i});
            case 'forwarded',  y = 3; c = col.forwarded;  lbl = sprintf('to SDR %g', L.nextId(i));
            case 'originated', y = 4; c = col.originated; lbl = sprintf('to SDR %g', L.nextId(i));
            case 'delivered',  y = 5; c = col.delivered;  lbl = sprintf('msg %s', L.message{i});
            otherwise,         y = 1; c = col.problem;    lbl = ev;
        end
        plot(ax1, L.time(i), y, 'o', 'MarkerSize', 8, 'MarkerFaceColor', c, 'MarkerEdgeColor', 'k');
        text(ax1, L.time(i), y + 0.32, lbl, 'FontSize', 8, 'HorizontalAlignment', 'center', ...
             'Color', c * 0.8);
    end
    set(ax1, 'YTick', 1:5, 'YTickLabel', rows, 'YLim', [0.5 5.8], 'XLim', [0 tEnd]);
    grid(ax1, 'on');
    title(ax1, sprintf(['Repeater SDR %d: %d originated, %d forwarded, %d delivered here, ' ...
          '%d ignored   (bursts of %d slots, %.0f ms dwell)'], stats.myId, stats.originated, ...
          stats.forwarded, numel(stats.delivered), stats.ignored, stats.burstSlots, 1e3*stats.dwell));
    ylabel(ax1, 'Decision');

    % ---------------- 2. Own bursts ----------------
    ax2 = subplot(3, 1, 2); hold(ax2, 'on');
    nCh = fh.nCh;
    shadeTx(ax2, bursts, [0.5 nCh + 0.5], col.tx);
    for b = 1:numel(bursts)
        chs = bursts(b).channels(:)';
        n = numel(chs);
        slotLen = (bursts(b).tEnd - bursts(b).tStart) / max(n, 1);   % measured, not the dwell
        t = bursts(b).tStart + (0:n) * slotLen;
        if strcmp(bursts(b).kind, 'originated'), c = col.originated; else, c = col.forwarded; end
        stairs(ax2, t, [chs, chs(end)], '-', 'Color', c, 'LineWidth', 1.5);
        plot(ax2, t(1:n) + slotLen/2, chs, 'o', 'MarkerSize', 4, 'MarkerFaceColor', c, ...
             'MarkerEdgeColor', 'none');
        text(ax2, bursts(b).tStart, nCh + 0.2, sprintf('%s to SDR %g', bursts(b).kind, ...
             bursts(b).nextId), 'FontSize', 8, 'VerticalAlignment', 'bottom', 'Color', c * 0.8);
    end
    if isempty(bursts)
        text(ax2, tEnd/2, (nCh + 1)/2, 'No bursts sent by this node', ...
             'HorizontalAlignment', 'center', 'Color', [0.4 0.4 0.4]);
    end
    tickStep = max(1, ceil(nCh / 10));
    set(ax2, 'YLim', [0.5 nCh + 1.2], 'YTick', 1:tickStep:nCh, 'XLim', [0 tEnd]);
    grid(ax2, 'on');
    ylabel(ax2, 'Channel');
    title(ax2, sprintf('Bursts sent: channel of every slot (%.3f - %.3f MHz)', fh.edges/1e6));

    % ---------------- 3. Packets heard ----------------
    ax3 = subplot(3, 1, 3); hold(ax3, 'on');
    bin = 0.5;                                          % seconds per bar
    nBins = ceil(tEnd / bin);
    good = countIn(stats.pktTimes, bin, nBins);
    bad  = countIn(stats.badTimes, bin, nBins);
    yTop = max([good + bad; 1]) / bin * 1.15;
    shadeTx(ax3, bursts, [0 yTop], col.tx);
    centres = ((1:nBins) - 0.5) * bin;
    hb = bar(ax3, centres, [good, bad] / bin, 1, 'stacked', 'EdgeColor', 'none');
    set(hb(1), 'FaceColor', col.good);
    set(hb(2), 'FaceColor', col.bad);
    set(ax3, 'XLim', [0 tEnd], 'YLim', [0 yTop]);
    grid(ax3, 'on');
    ylabel(ax3, 'Packets / s');
    xlabel(ax3, 'Time since the radio started (s)');
    legend(ax3, hb, {sprintf('Good (%d)', numel(stats.pktTimes)), ...
           sprintf('Checksum failed (%d)', numel(stats.badTimes))}, 'Location', 'northeast');
    title(ax3, 'Packets received (grey = this node transmitting, deaf)');

    linkaxes([ax1, ax2, ax3], 'x');
end

% ======================================================================
function shadeTx(ax, bursts, yl, c)
% Grey band for every burst this node sent.
    for b = 1:numel(bursts)
        patch(ax, [bursts(b).tStart bursts(b).tEnd bursts(b).tEnd bursts(b).tStart], ...
              [yl(1) yl(1) yl(2) yl(2)], c, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
end

function n = countIn(t, bin, nBins)
    n = zeros(nBins, 1);
    if isempty(t), return; end
    k = min(max(floor(t(:) / bin) + 1, 1), nBins);
    n = accumarray(k, 1, [nBins, 1]);
end

function s = forText(routeHex)
% "for SDR n": the SDR the heard burst was meant for.
    s = 'not mine';
    try
        ids = hexToSdrList(routeHex);
        if ~isempty(ids), s = sprintf('for SDR %d', ids(1)); end
    catch
    end
end
