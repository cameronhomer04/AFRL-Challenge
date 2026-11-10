function out = fhHopDisplay(action, varargin)
% FHHOPDISPLAY  Live picture of the system hopping, slot by slot.
%
%   d = fhHopDisplay('create', fh)
%   d = fhHopDisplay('create', fh, nShow)      % most slots shown at once (default 60)
%   keepRunning = fhHopDisplay('update', d, fh, slotLog, chStats)
%
%   fh      - struct from fhConfig (fh.allowed = channels still in use)
%   slotLog - struct of column vectors, one row per slot (fhRunLoopback):
%             slot, channel, pass, pktsReceived, pktsSent, snrDb
%   chStats - struct with 1-by-nCh vectors: visits, passes, pktsSent, pktsReceived
%
% Window:
%   top          hop sequence: the channel of every slot, joined in order.
%                Green dot = the message was received in that slot,
%                red cross = it was not; the newest slot is circled.
%                With 20 channels or fewer every channel gets its own
%                labelled row and each point is labelled with its channel.
%                Grey rows = excluded channels. The view starts 20 slots
%                wide, grows to nShow slots, then scrolls.
%   bottom left  packets received on each channel (% of packets sent there),
%                labelled with slots passed / slots visited.
%                Green = in use, grey = excluded, empty = not visited yet.
%   bottom right packets received in each slot (% of sent, bars) and the
%                estimated SNR of the slot (line, right axis).
%
%   keepRunning - false once the window is closed

    switch lower(action)
        case 'create'
            out = createDisplay(varargin{:});
        case 'update'
            out = updateDisplay(varargin{:});
        otherwise
            error('fhHopDisplay:action', 'Action must be ''create'' or ''update''.');
    end
end

% ======================================================================
function d = createDisplay(fh, nShow)
    if nargin < 2, nShow = 60; end
    d.nShow    = nShow;
    d.minShow  = min(20, nShow);
    d.fewCh    = fh.nCh <= 20;                    % room to label every channel
    green = [0.20 0.65 0.30]; red = [0.85 0.20 0.15];

    d.fig = figure('Name', 'Frequency hopping', 'NumberTitle', 'off', ...
                   'Color', 'w', 'Position', [100 60 1150 760]);

    % ---- Hop sequence ----
    d.axHop = subplot(2, 2, [1 2]);
    hold(d.axHop, 'on'); grid(d.axHop, 'on'); box(d.axHop, 'on');
    set(d.axHop, 'FontSize', 10);
    d.hExcl = plot(d.axHop, NaN, NaN, '-', 'Color', [0.80 0.80 0.80], 'LineWidth', 6);
    d.hPath = plot(d.axHop, NaN, NaN, '-', 'Color', [0.60 0.70 0.90], 'LineWidth', 1);
    d.hOk   = plot(d.axHop, NaN, NaN, 'o', 'MarkerSize', 8, ...
                   'MarkerFaceColor', green, 'MarkerEdgeColor', [0.10 0.40 0.15]);
    d.hFail = plot(d.axHop, NaN, NaN, 'x', 'MarkerSize', 11, 'LineWidth', 2.5, 'Color', red);
    d.hNow  = plot(d.axHop, NaN, NaN, 'o', 'MarkerSize', 16, 'LineWidth', 1.5, ...
                   'Color', [0.10 0.10 0.10]);
    fMHz = fh.freqs / 1e6;
    pad = 0.6 * fh.spacing / 1e6;
    ylim(d.axHop, [min(fMHz) - pad, max(fMHz) + pad]);
    if d.fewCh
        labels = arrayfun(@(c) sprintf('ch %d   %.2f', c, fMHz(c)), 1:fh.nCh, ...
                          'UniformOutput', false);
        set(d.axHop, 'YTick', fMHz, 'YTickLabel', labels);
        ylabel(d.axHop, 'Channel   frequency (MHz)');
    else
        ylabel(d.axHop, 'Channel frequency (MHz)');
    end
    xlim(d.axHop, [-0.5, d.minShow - 0.5]);
    xlabel(d.axHop, 'Slot');
    d.hopTitle = title(d.axHop, 'Hop sequence', 'FontSize', 12);
    legend(d.axHop, [d.hOk, d.hFail, d.hNow], {'message received', 'missed', 'newest slot'}, ...
           'Location', 'eastoutside');

    % ---- Packets received per channel ----
    d.axCh = subplot(2, 2, 3);
    d.hBar = bar(d.axCh, 1:fh.nCh, zeros(1, fh.nCh), 0.7, 'FaceColor', 'flat', ...
                 'EdgeColor', [0.30 0.30 0.30]);
    d.hBar.CData = repmat(green, fh.nCh, 1);
    hold(d.axCh, 'on'); grid(d.axCh, 'on'); box(d.axCh, 'on');
    set(d.axCh, 'FontSize', 10);
    ylim(d.axCh, [0 115]); xlim(d.axCh, [0.4, fh.nCh + 0.6]);
    if d.fewCh
        set(d.axCh, 'XTick', 1:fh.nCh);
    end
    xlabel(d.axCh, 'Channel'); ylabel(d.axCh, 'Packets received (% of sent)');
    if d.fewCh
        title(d.axCh, {'Packets received per channel', ...
                       '(label = slots passed / slots on that channel; grey = excluded)'}, ...
              'FontSize', 11);
    else
        title(d.axCh, 'Packets received per channel (grey = excluded)', 'FontSize', 11);
    end

    % ---- Packets and SNR per slot ----
    d.axPk = subplot(2, 2, 4);
    set(d.axPk, 'FontSize', 10);
    yyaxis(d.axPk, 'left');
    d.hPk = bar(d.axPk, 0, 0, 0.7, 'FaceColor', [0.30 0.50 0.80], 'EdgeColor', 'none');
    ylabel(d.axPk, 'Packets received (% of sent)'); ylim(d.axPk, [0 115]);
    yyaxis(d.axPk, 'right');
    d.hSnr = plot(d.axPk, NaN, NaN, 'o-', 'Color', [0.85 0.45 0.10], ...
                  'MarkerFaceColor', [0.85 0.45 0.10], 'MarkerSize', 4, 'LineWidth', 1.2);
    ylabel(d.axPk, 'SNR estimate (dB)');
    grid(d.axPk, 'on'); box(d.axPk, 'on');
    xlabel(d.axPk, 'Slot');
    xlim(d.axPk, [-0.5, d.minShow - 0.5]);
    title(d.axPk, {'Packets received (bars) and SNR (line) per slot', ''}, 'FontSize', 11);

    drawnow;
end

% ======================================================================
function keepRunning = updateDisplay(d, fh, L, chStats)
    keepRunning = isgraphics(d.fig);
    if ~keepRunning || isempty(L.slot)
        return;
    end
    delete(findobj(d.fig, 'Tag', 'fhLabel'));          % last update's text labels

    % ---- Which slots to show: at least minShow wide, at most nShow ----
    n = numel(L.slot);
    show = max(1, n - d.nShow + 1) : n;
    s  = L.slot(show);  s  = s(:);
    chs = L.channel(show); chs = chs(:);
    f  = fh.freqs(chs) / 1e6;  f = f(:);
    ok = logical(L.pass(show));  ok = ok(:);
    x0 = s(1) - 0.5;
    x1 = max(s(end) + 1, s(1) + d.minShow) - 0.5;

    % ---- Hop sequence ----
    set(d.hPath, 'XData', s, 'YData', f);
    set(d.hOk,   'XData', s(ok),  'YData', f(ok));
    set(d.hFail, 'XData', s(~ok), 'YData', f(~ok));
    set(d.hNow,  'XData', s(end), 'YData', f(end));
    xlim(d.axHop, [x0 x1]);
    if d.fewCh && numel(show) <= 40                    % channel number next to each point
        text(d.axHop, s + 0.15, f + 0.25*fh.spacing/1e6, ...
             arrayfun(@(c) sprintf('%d', c), chs, 'UniformOutput', false), ...
             'FontSize', 8, 'Color', [0.30 0.30 0.30], 'Tag', 'fhLabel');
    end

    allowed = 1:fh.nCh;
    if isfield(fh, 'allowed') && ~isempty(fh.allowed), allowed = fh.allowed; end
    excl = setdiff(1:fh.nCh, allowed);
    if isempty(excl)
        set(d.hExcl, 'XData', NaN, 'YData', NaN);
    else
        fx = fh.freqs(excl) / 1e6;
        xs = repmat([x0; x1; NaN], 1, numel(excl));
        ys = [fx; fx; NaN(1, numel(excl))];
        set(d.hExcl, 'XData', xs(:), 'YData', ys(:));
    end

    nPass = sum(L.pass);
    d.hopTitle.String = sprintf(['Hop sequence: slot %d on channel %d (%.2f MHz)   |   ' ...
        '%d of %d slots received the message   |   %d channels in use'], ...
        s(end), chs(end), f(end), nPass, n, numel(allowed));

    % ---- Packets received per channel ----
    pct = 100 * chStats.pktsReceived ./ max(chStats.pktsSent, 1);
    c = repmat([0.20 0.65 0.30], fh.nCh, 1);
    c(excl, :) = repmat([0.65 0.65 0.65], numel(excl), 1);
    set(d.hBar, 'YData', pct, 'CData', c);
    if d.fewCh
        for k = find(chStats.visits > 0)
            text(d.axCh, k, pct(k) + 3, sprintf('%d/%d', chStats.passes(k), chStats.visits(k)), ...
                 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                 'FontSize', 9, 'Tag', 'fhLabel');
        end
    end

    % ---- Packets and SNR per slot ----
    pctSlot = 100 * L.pktsReceived(show) ./ max(L.pktsSent(show), 1);
    yyaxis(d.axPk, 'left');
    set(d.hPk, 'XData', s, 'YData', pctSlot(:));
    yyaxis(d.axPk, 'right');
    snr = L.snrDb(show);
    set(d.hSnr, 'XData', s, 'YData', snr(:));
    good = snr(isfinite(snr));
    if ~isempty(good)                                  % keep the line readable
        lo = floor(min(good) / 5) * 5 - 5;
        hi = ceil(max(good) / 5) * 5 + 5;
        ylim(d.axPk, [lo, max(hi, lo + 10)]);
    end
    xlim(d.axPk, [x0 x1]);
    % bar() sets a tick under every bar; let MATLAB space them instead
    set(d.axPk, 'XTickMode', 'auto', 'XTickLabelMode', 'auto');
    title(d.axPk, {'Packets received (bars) and SNR (line) per slot', ...
                   sprintf('last slot: %.0f%% of packets, SNR %.1f dB', pctSlot(end), snr(end))}, ...
          'FontSize', 11);

    drawnow limitrate;
end
