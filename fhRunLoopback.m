function stats = fhRunLoopback(cfg, fh, sdr, hexMessages, opts)
% FHRUNLOOPBACK  Frequency-hopping loopback test on ONE radio: the node
% transmits and receives on the same hop sequence, checks every packet of
% every slot, and drops channels that keep failing.
%
%   stats = fhRunLoopback(cfg, fh, sdr, hexMessages, opts)
%
%   cfg         - settings from qpskConfig
%   fh          - struct from fhConfig plus slotGuard / pktGap / allowed
%                 (see runNode_FH)
%   sdr         - node from setupSdrNode with role "both" (tx and rx objects;
%                 the same radio, or [txRadio, rxRadio] on one computer).
%                 The receiver must NOT be in burst mode.
%   hexMessages - message(s) to send, as in fhRunTransmitter
%   opts        - struct, any field may be left out:
%       duration          seconds to run; Inf = until Stop / Ctrl+C (default)
%       messageInterval   seconds on each message before the next (default 5)
%       showDisplay       live receiver window (default true)
%       showHopDisplay    hop sequence window, see fhHopDisplay (default true)
%       printEachSlot     one line per slot in the Command Window (default true)
%       routeMode         true if every message starts with an A* routing
%                         number (fhAddRoute); adds the route columns (default false)
%       myId              this node's SDR ID in the A* bank (default NaN)
%       minPacketsPerSlot packets with the right message needed for the
%                         slot to PASS (default 1)
%       adaptive          drop channels that keep failing (default true)
%       surveyVisits      visits to every channel before judging it (default 2)
%       minPassRate       channels passing less often than this are
%                         dropped (default 0.5)
%       minPacketRate     channels delivering less than this part of the
%                         packets sent are dropped too, even if their
%                         slots pass (default 0.5)
%       minChannels       never hop over fewer channels than this (default 25)
%       framesPerBlock    frames per window shown in the live window (default 4)
%       warmupSlots       first slots while the radio starts up: logged and
%                         printed but left out of every count and channel
%                         review (default 1)
%       extraFrames       frames still recorded after the slot ends, to cover
%                         the delay from TX to RX inside the radio (default 12,
%                         about 60 ms; a B210 on USB can delay by 20-40 ms)
%       maxFlushFrames    most stale RX frames thrown away after a hop (default 32)
%
%   stats - totals, plus
%       slotLog  struct of column vectors, ONE ROW PER SLOT (the proof):
%           slot, time, channel, freqMHz, message, receivedMessage,
%           receivedRoute, routeSdrs, myIdOnRoute, sentText, receivedText, pktsSent,
%           pktsReceived, pktsMatched, pass, wrongSlot, checksumFailed,
%           bitErrors, bitsCompared, meanMetric, freqOffsetHz, peakDbfs, snrDb,
%           missedPkts (packet numbers not received, e.g. '32-38'),
%           warmup (true for start-up slots, which are not counted)
%           With routeMode on (A* routing number in every payload):
%           receivedRoute = routing number decoded in this slot, routeSdrs =
%           the SDR IDs it lists, myIdOnRoute = 1 if opts.myId is on it,
%           0 if not, NaN if no route was decoded.
%           sentText / receivedText = the message part alone, without the
%           route length and route (the whole payload when routeMode is off).
%           message is what was sent; receivedMessage is what was decoded
%           from this slot's packets: the text alone if every packet agreed,
%           'TEXT (count) | TEXT (count)' if they differed, '(none)' if no
%           packet of this slot was decoded.
%           Turn it into a table with struct2table(stats.slotLog).
%       chStats  per channel: visits, passes, pktsSent, pktsReceived,
%                bitErrors, bits
%       excluded channels dropped during the run (also in fh.allowed)
%
% Each slot:
%   1. both the TX and the RX are retuned to the slot's channel,
%   2. stale RX samples from the previous channel are thrown away,
%   3. the slot is sent one frame at a time, reading one RX frame after
%      each TX frame, so both stream together,
%   4. every packet in the recording is decoded and checked: header (slot
%      and packet number), checksum, and message bit by bit vs. what was sent.
%   5. the slot PASSES when at least minPacketsPerSlot packets carry the
%      right slot number AND exactly the message that was sent.
% While steps 4-5 run nothing is transmitted (the TX reports underruns and
% the RX overflows). That only adds silence between slots and is expected.
%
% Channel exclusion (adaptive = true): once every channel in use has been
% visited surveyVisits times, channels passing less than minPassRate of
% their slots, or delivering less than minPacketRate of their packets, are
% dropped, and the check repeats every surveyVisits passes
% through the channels. The hop sequence continues over the channels left.
% A single radio can change its own list at any time; for "tx" and "rx" on
% two radios, copy the printed list into excludeChannels in runNode_FH on
% BOTH nodes so they keep hopping together.

    if nargin < 5, opts = struct(); end
    opts = fillDefaults(opts);
    if isempty(sdr.tx) || isempty(sdr.rx)
        error('fhRunLoopback needs a node with role "both".');
    end
    if ~isfield(fh, 'allowed') || isempty(fh.allowed)
        fh.allowed = 1:fh.nCh;
    end

    % ---- Messages and their slot layouts ----
    messages = cellstr(hexMessages);
    nMsg = numel(messages);
    layouts = cell(nMsg, 1);
    refBits = cell(nMsg, 1);
    for m = 1:nMsg
        [refBits{m}, messages{m}] = hexToBits(messages{m});
        if numel(messages{m}) + 12 > cfg.maxHexChars
            error('Message %d is %d hex characters; with the 12-character hop header the maximum is %d.', ...
                  m, numel(messages{m}), cfg.maxHexChars - 12);
        end
        layouts{m} = fhPacketLayout(cfg, fh, 12 + numel(messages{m}));
    end

    spf = cfg.samplesPerFrame;
    sps = cfg.samplesPerSymbol;
    winSamples = opts.framesPerBlock * spf;
    neededSamples = (2*cfg.maxPacketSymbols + 2*cfg.filterSpan + 10) * sps;
    if winSamples < neededSamples
        error('framesPerBlock = %d is too small; use at least %d.', ...
              opts.framesPerBlock, ceil(neededSamples / spf));
    end
    % Scan windows: receivePacket only accepts a packet that starts in the
    % first (window - longest packet) samples, so windows this long, stepped
    % by scanStep, look for every packet start exactly once.
    scanSyms = 128;                                    % start region per window (symbols)
    scanStep = scanSyms * sps;
    scanWin  = (cfg.maxPacketSymbols + scanSyms + 5) * sps;

    cleanup = onCleanup(@() releaseSdrNode(sdr)); %#ok<NASGU>  % runs on return, error or Ctrl+C

    % ---- Statistics ----
    stats.slots = 0; stats.slotsPassed = 0;
    stats.pktsSent = 0; stats.pktsReceived = 0; stats.pktsMatched = 0;
    stats.checksumFailed = 0; stats.wrongSlot = 0;
    stats.bitErrors = 0; stats.bitsCompared = 0;
    stats.underruns = 0; stats.overflows = 0;
    stats.excluded = [];
    z = zeros(1, fh.nCh);
    chStats = struct('visits', z, 'passes', z, 'pktsSent', z, 'pktsReceived', z, ...
                     'bitErrors', z, 'bits', z);
    win = struct('visits', z, 'passes', z, 'pktsSent', z, 'pktsReceived', z);  % since the last review
    L = emptyLog();
    metricHistory = zeros(0, 1);
    reviewDue = opts.surveyVisits * numel(fh.allowed);   % slots until the first review
    slotsSinceReview = 0;

    display = [];
    if opts.showDisplay
        display = createLiveRxDisplay(cfg);
    end
    hopDisplay = [];
    if opts.showHopDisplay
        hopDisplay = fhHopDisplay('create', fh);
    end
    lay = layouts{1};
    fprintf('\nHopping loopback over %d channels: %d packets per %.0f ms slot.\n', ...
            numel(fh.allowed), lay.pktsPerSlot, 1e3*fh.dwell);
    fprintf('A slot PASSES when %d or more packets carry its slot number and the exact message sent.\n', ...
            opts.minPacketsPerSlot);
    if opts.adaptive
        fprintf(['Channels passing under %.0f%% of their slots, or receiving under %.0f%% of their packets,\n' ...
                 'are dropped after %d visits each (first review after %d slots).\n'], ...
                100*opts.minPassRate, 100*opts.minPacketRate, opts.surveyVisits, reviewDue);
    end
    if ~isempty(display) || ~isempty(hopDisplay)
        fprintf('Close a window, press Stop, or Ctrl+C to end.\n');
    else
        fprintf('Press Ctrl+C to end.\n');
    end

    slot = 0;
    msgIndex = 1;
    lastSwitch = tic;
    lastSummary = 0;
    runTimer = tic;
    fprintf('[%7.1f s] Message: %s\n', 0, messages{msgIndex});

    while toc(runTimer) < opts.duration
        if nMsg > 1 && toc(lastSwitch) >= opts.messageInterval
            msgIndex = mod(msgIndex, nMsg) + 1;
            lastSwitch = tic;
            fprintf('[%7.1f s] Message: %s\n', toc(runTimer), messages{msgIndex});
        end
        msg = messages{msgIndex};
        lay = layouts{msgIndex};
        ref = refBits{msgIndex};

        % ---- 1. Hop both sides ----
        frame = fhBuildSlotFrame(cfg, lay, slot, msg);
        [ch, fHz] = fhHopSequence(fh, slot);
        fhTune(sdr.tx, fh, ch);
        fhTune(sdr.rx, fh, ch);

        % ---- 2. Throw away RX samples left from before the hop ----
        for k = 1:opts.maxFlushFrames
            [~, ~, ov] = sdr.rx();
            if ov, break; end
        end

        % ---- 3. Send the slot and record it at the same time ----
        nChunks = ceil(numel(frame) / spf);
        frame(end+1 : nChunks*spf) = 0;
        rec = complex(zeros((nChunks + opts.extraFrames) * spf, 1));
        nRec = 0;
        for c = 1:nChunks + opts.extraFrames
            if c <= nChunks
                % complex() is required: MATLAB turns an all-zero slice of a
                % complex array (the silent lead-in) into a real one, and the
                % transmitter rejects a change between real and complex input.
                chunk = complex(frame((c-1)*spf + (1:spf)));
                stats.underruns = stats.underruns + double(sdr.tx(chunk));
            end
            [d, len, ov] = sdr.rx();
            rec(nRec + (1:len)) = d(1:len);
            nRec = nRec + len;
            stats.overflows = stats.overflows + double(ov);
        end
        rec = double(rec(1:nRec));
        tSlot = toc(runTimer);
        % Pad the end with silence: receivePacket only searches for a packet
        % that has room for the LONGEST possible packet after it, so without
        % this the last ~6 ms of the recording would never be searched.
        rec = [rec; zeros(scanWin, 1)];

        % ---- 4. Decode every packet in the recording ----
        % Short windows step through the whole recording; each can find one
        % packet starting in its first scanStep samples, so every packet is
        % looked for once, wherever it landed. Each packet names itself in
        % its header (slot and packet number), so no timing is assumed.
        seen = false(1, lay.pktsPerSlot);
        pktsReceived = 0; pktsMatched = 0; nWrongSlot = 0; nChecksum = 0;
        bitErr = 0; bitsCmp = 0; metrics = []; offsets = []; peaks = [];
        rxTexts = {};                     % decoded message of each packet of this slot
        lastRx = []; lastWin = rec(1:min(winSamples, end));
        bestMetric = 0;                   % best preamble match in this slot
        for s0 = 0 : scanStep : numel(rec) - scanWin
            w = rec(s0 + (1:scanWin));
            [r, hSlot, k, payloadBits] = decodeOne(cfg, w);
            if ~isempty(r), bestMetric = max(bestMetric, r.sync.metric); end
            if isempty(r) || ~r.detected, continue; end
            if isnan(hSlot)
                nChecksum = nChecksum + 1;
                continue;
            end
            if hSlot ~= slot
                nWrongSlot = nWrongSlot + 1;
                continue;
            end
            if k >= lay.pktsPerSlot || seen(k+1), continue; end   % found twice
            seen(k+1) = true;
            lastRx = r; lastWin = w;
            pktsReceived = pktsReceived + 1;
            rxTexts{end+1} = r.hexMessage(13:end); %#ok<AGROW>  without the 12-char header
            metrics(end+1) = r.sync.metric;   %#ok<AGROW>
            offsets(end+1) = r.freqOffsetHz;  %#ok<AGROW>
            peaks(end+1) = r.peakDbfs;        %#ok<AGROW>
            if numel(payloadBits) == numel(ref)
                e = sum(payloadBits ~= ref);
                bitErr = bitErr + e;
                bitsCmp = bitsCmp + numel(ref);
                pktsMatched = pktsMatched + (e == 0);
            end
        end
        pass = pktsMatched >= opts.minPacketsPerSlot;
        metricHistory(end+1, 1) = bestMetric;   %#ok<AGROW>  one point per slot, never empty

        % ---- 5. Record the slot ----
        snrDb = estimateSnr(rec(1:end-scanWin));   % without the silent padding
        [rxRoute, rxSdrs, onRoute, rxText] = routeInfo(rxTexts, opts);
        sentText = messagePart(msg, opts);    % sent message without the route
        isWarmup = slot < opts.warmupSlots;   % radio still starting: logged, not counted
        missedText = rangeText(find(~seen) - 1);
        L = appendLog(L, slot, tSlot, ch, fHz/1e6, msg, summarizeTexts(rxTexts), ...
                      rxRoute, rxSdrs, onRoute, sentText, rxText, lay.pktsPerSlot, ...
                      pktsReceived, pktsMatched, pass, nWrongSlot, nChecksum, bitErr, bitsCmp, ...
                      meanOrNaN(metrics), meanOrNaN(offsets), maxOrNaN(peaks), snrDb, ...
                      missedText, isWarmup);

        if isWarmup
            if opts.printEachSlot
                fprintf('[%7.1f s] slot %5d  ch %2d  %.3f MHz  warm-up (not counted)  packets %2d/%2d\n', ...
                        tSlot, slot, ch, fHz/1e6, pktsReceived, lay.pktsPerSlot);
            end
            slot = slot + 1;
            continue;
        end
        stats.slots        = stats.slots + 1;
        stats.slotsPassed  = stats.slotsPassed + pass;
        stats.pktsSent     = stats.pktsSent + lay.pktsPerSlot;
        stats.pktsReceived = stats.pktsReceived + pktsReceived;
        stats.pktsMatched  = stats.pktsMatched + pktsMatched;
        stats.checksumFailed = stats.checksumFailed + nChecksum;
        stats.wrongSlot    = stats.wrongSlot + nWrongSlot;
        stats.bitErrors    = stats.bitErrors + bitErr;
        stats.bitsCompared = stats.bitsCompared + bitsCmp;
        chStats.visits(ch)       = chStats.visits(ch) + 1;
        chStats.passes(ch)       = chStats.passes(ch) + pass;
        chStats.pktsSent(ch)     = chStats.pktsSent(ch) + lay.pktsPerSlot;
        chStats.pktsReceived(ch) = chStats.pktsReceived(ch) + pktsReceived;
        chStats.bitErrors(ch)    = chStats.bitErrors(ch) + bitErr;
        chStats.bits(ch)         = chStats.bits(ch) + bitsCmp;
        win.visits(ch) = win.visits(ch) + 1;
        win.passes(ch) = win.passes(ch) + pass;
        win.pktsSent(ch)     = win.pktsSent(ch) + lay.pktsPerSlot;
        win.pktsReceived(ch) = win.pktsReceived(ch) + pktsReceived;

        if opts.printEachSlot
            if pass, verdict = 'PASS'; else, verdict = 'FAIL'; end
            fprintf('[%7.1f s] slot %5d  ch %2d  %.3f MHz  %s  packets %2d/%2d (%2d exact)  bit errors %d  SNR %4.1f dB\n', ...
                    tSlot, slot, ch, fHz/1e6, verdict, pktsReceived, lay.pktsPerSlot, ...
                    pktsMatched, bitErr, snrDb);
            if pktsReceived < lay.pktsPerSlot
                fprintf('           missed packet(s) %s\n', missedText);
            end
            if opts.routeMode
                if isnan(onRoute), onText = '-'; elseif onRoute, onText = 'yes'; else, onText = 'no'; end
                fprintf('           route %s -> SDRs %s   SDR %d on route: %s   message %s\n', ...
                        rxRoute, rxSdrs, opts.myId, onText, rxText);
            end
        end

        % ---- 6. Review the channels ----
        slotsSinceReview = slotsSinceReview + 1;
        if opts.adaptive && slotsSinceReview >= reviewDue
            [fh, dropped] = reviewChannels(fh, win, opts);
            if ~isempty(dropped)
                stats.excluded = sort([stats.excluded, dropped]);
                fprintf(['[%7.1f s] Dropped channel(s) %s (%s MHz): under %.0f%% of slots passed\n' ...
                         '           or under %.0f%% of packets received. Now hopping over %d channels.\n' ...
                         '           Excluded so far: %s\n'], ...
                        toc(runTimer), mat2str(dropped), mat2str(round(fh.freqs(dropped)/1e3)/1e3), ...
                        100*opts.minPassRate, 100*opts.minPacketRate, numel(fh.allowed), ...
                        mat2str(stats.excluded));
            end
            win.visits(:) = 0; win.passes(:) = 0;
            slotsSinceReview = 0;
            reviewDue = opts.surveyVisits * numel(fh.allowed);
        end

        % ---- Windows ----
        statusLines = { ...
            sprintf('Slot %d  |  ch %d  %.3f MHz  |  %s  |  packets %d/%d  |  message %s', ...
                    slot, ch, fHz/1e6, ternary(pass, 'PASS', 'FAIL'), pktsReceived, lay.pktsPerSlot, msg), ...
            sprintf('Slots passed %d of %d  |  packets %d/%d  |  wrong slot %d  |  channels in use %d', ...
                    stats.slotsPassed, stats.slots, stats.pktsReceived, stats.pktsSent, ...
                    stats.wrongSlot, numel(fh.allowed)), ...
            sprintf('BER %.2e (%d/%d bits)', stats.bitErrors / max(stats.bitsCompared, 1), ...
                    stats.bitErrors, stats.bitsCompared)};
        keepRunning = true;
        if ~isempty(hopDisplay)
            keepRunning = fhHopDisplay('update', hopDisplay, fh, L, chStats);
        end
        if keepRunning && ~isempty(display)
            if isempty(lastRx)
                try
                    lastRx = receivePacket(cfg, lastWin);
                catch
                    lastRx = receivePacket(cfg, 1e-6 * ones(winSamples, 1));
                end
            end
            keepRunning = updateLiveRxDisplay(display, cfg, lastWin, lastRx, metricHistory, statusLines);
        end
        if ~keepRunning
            break;                                       % Stop pressed / window closed
        end
        if ~opts.printEachSlot && toc(runTimer) - lastSummary >= 5
            lastSummary = toc(runTimer);
            fprintf('[%7.1f s] %s\n', lastSummary, statusLines{2});
        end
        slot = slot + 1;
    end

    stats.duration = toc(runTimer);
    stats.metricHistory = metricHistory;
    stats.BER = stats.bitErrors / max(stats.bitsCompared, 1);
    stats.slotLog = L;
    stats.chStats = chStats;
    stats.allowed = fh.allowed;

    % ---- Summary ----
    fprintf('\n--- Hopping loopback summary (%.1f s) ---\n', stats.duration);
    fprintf('Slots passed: %d of %d (%.1f%%)\n', stats.slotsPassed, stats.slots, ...
            100*stats.slotsPassed/max(stats.slots, 1));
    fprintf('Packets received: %d of %d sent (%.1f%%), %d with the exact message\n', ...
            stats.pktsReceived, stats.pktsSent, 100*stats.pktsReceived/max(stats.pktsSent, 1), ...
            stats.pktsMatched);
    fprintf('Bit errors: %d / %d   BER: %.2e\n', stats.bitErrors, stats.bitsCompared, stats.BER);
    fprintf('Checksum failed: %d   Wrong slot: %d\n', stats.checksumFailed, stats.wrongSlot);
    failed = L.slot(~L.pass & ~L.warmup);
    if ~isempty(failed)
        fprintf('Slots that failed: %s\n', mat2str(failed(1:min(end, 30))'));
    end
    fprintf('\nChannel  MHz       visits  passed  packets rx/sent   BER\n');
    for c = find(chStats.visits > 0)
        tag = '';
        if any(stats.excluded == c), tag = '  EXCLUDED'; end
        fprintf('  %3d   %8.3f   %4d    %4d    %6d/%-6d    %.1e%s\n', c, fh.freqs(c)/1e6, ...
                chStats.visits(c), chStats.passes(c), chStats.pktsReceived(c), ...
                chStats.pktsSent(c), chStats.bitErrors(c) / max(chStats.bits(c), 1), tag);
    end
    notVisited = setdiff(fh.allowed, find(chStats.visits > 0));
    if ~isempty(notVisited)
        fprintf('Channels in use but not visited yet: %s\n', mat2str(notVisited));
    end
    if ~isempty(stats.excluded)
        fprintf('\nExcluded channels: %s\n', mat2str(stats.excluded));
        fprintf('For "tx" and "rx" on two radios, set on BOTH nodes in runNode_FH:\n');
        fprintf('  excludeChannels = %s;\n', mat2str(stats.excluded));
    end
    if stats.wrongSlot > 0
        fprintf('Packets from the wrong slot mean old samples reached the decoder:\n');
        fprintf('  raise maxFlushFrames or slotGuard.\n');
    end
    fprintf('Radios released.\n');
end

% ======================================================================
function [r, hSlot, k, payloadBits] = decodeOne(cfg, w)
% Decode one window. hSlot = NaN if no packet, a bad checksum or a bad header.
    hSlot = NaN; k = NaN; payloadBits = [];
    try
        r = receivePacket(cfg, w);
    catch
        r = [];
        return;
    end
    if ~r.detected || ~r.valid || ~r.checksumOK || r.numHexChars < 13
        return;
    end
    [s, kk, ok] = fhReadHeader(hexToBits(r.hexMessage(1:12)));
    if ok
        hSlot = s; k = kk;
        payloadBits = r.payloadBits(49:end);
    end
end

function [fh, dropped] = reviewChannels(fh, win, opts)
% Drop channels in use whose pass rate since the last review is too low,
% keeping at least opts.minChannels (the best ones).
    allowed = fh.allowed;
    seen = allowed(win.visits(allowed) > 0);
    rate = win.passes(seen) ./ win.visits(seen);
    pktRate = win.pktsReceived(seen) ./ max(win.pktsSent(seen), 1);
    bad = seen(rate < opts.minPassRate | pktRate < opts.minPacketRate);
    keep = setdiff(allowed, bad);
    if numel(keep) < opts.minChannels
        need = min(opts.minChannels, numel(allowed)) - numel(keep);
        [~, order] = sort(win.pktsReceived(bad) ./ max(win.pktsSent(bad), 1), 'descend');
        keep = sort([keep, bad(order(1:need))]);
    end
    dropped = setdiff(allowed, keep);
    if numel(keep) >= 2
        fh.allowed = keep;
    else
        dropped = [];
    end
end

function snrDb = estimateSnr(rec)
% Slot SNR from the recording: busy segments (packets) against quiet ones
% (the guard silence before and after the slot).
    seg = 512;
    n = floor(numel(rec) / seg);
    if n < 10, snrDb = NaN; return; end
    p = sort(mean(abs(reshape(rec(1:n*seg), seg, n)).^2, 1));
    noise = p(max(1, round(0.05*n)));
    sig = p(round(0.75*n));
    snrDb = 10*log10(max(sig - noise, eps) / max(noise, eps));
end

function L = emptyLog()
    L = struct('slot', zeros(0,1), 'time', zeros(0,1), 'channel', zeros(0,1), ...
               'freqMHz', zeros(0,1), 'message', {cell(0,1)}, ...
               'receivedMessage', {cell(0,1)}, 'receivedRoute', {cell(0,1)}, ...
               'routeSdrs', {cell(0,1)}, 'myIdOnRoute', zeros(0,1), ...
               'sentText', {cell(0,1)}, 'receivedText', {cell(0,1)}, 'pktsSent', zeros(0,1), ...
               'pktsReceived', zeros(0,1), 'pktsMatched', zeros(0,1), ...
               'pass', false(0,1), 'wrongSlot', zeros(0,1), 'checksumFailed', zeros(0,1), ...
               'bitErrors', zeros(0,1), 'bitsCompared', zeros(0,1), 'meanMetric', zeros(0,1), ...
               'freqOffsetHz', zeros(0,1), 'peakDbfs', zeros(0,1), 'snrDb', zeros(0,1), ...
               'missedPkts', {cell(0,1)}, 'warmup', false(0,1));
end

function L = appendLog(L, varargin)
    names = fieldnames(L);
    for i = 1:numel(names)
        v = varargin{i};
        if iscell(L.(names{i}))
            L.(names{i}){end+1, 1} = v;
        else
            L.(names{i})(end+1, 1) = v;
        end
    end
end

function s = summarizeTexts(texts)
% One text for the log: the message alone if every packet agreed, each
% distinct version with its count if not, '(none)' if nothing was decoded.
    if isempty(texts)
        s = '(none)';
        return;
    end
    [u, ~, idx] = unique(texts);
    if numel(u) == 1
        s = u{1};
        return;
    end
    counts = accumarray(idx(:), 1);
    [counts, order] = sort(counts, 'descend');
    parts = arrayfun(@(i) sprintf('%s (%d)', u{order(i)}, counts(i)), 1:numel(u), ...
                     'UniformOutput', false);
    s = strjoin(parts, ' | ');
end

function [routeHex, sdrText, onRoute, msgText] = routeInfo(texts, opts)
% Route carried by the most common message decoded in this slot, and the
% message part that follows it (msgText).
    routeHex = ''; sdrText = ''; onRoute = NaN; msgText = '';
    if isempty(texts)
        msgText = '(none)';
        if opts.routeMode, routeHex = '(none)'; end
        return;
    end
    [u, ~, idx] = unique(texts);
    [~, best] = max(accumarray(idx(:), 1));
    if ~opts.routeMode                  % no route in the payload: all of it is message
        msgText = u{best};
        return;
    end
    [r, m, ok, sdrList] = fhSplitRoute(u{best});
    if ~ok
        routeHex = '(invalid)'; msgText = '(invalid)';
        return;
    end
    if isempty(m), m = '(none)'; end
    msgText = m;
    routeHex = r;
    sdrText = mat2str(sdrList(:)');
    if ~isnan(opts.myId)
        onRoute = double(any(sdrList == opts.myId));
    end
end

function m = messagePart(payload, opts)
% The message part of what was sent, without the route length and route.
    m = payload;
    if opts.routeMode
        [~, m, ok] = fhSplitRoute(payload);
        if ~ok, m = '(invalid)'; elseif isempty(m), m = '(none)'; end
    end
end

function t = rangeText(v)
% '3 7-9 12' style list of packet numbers; '' if none.
    t = '';
    if isempty(v), return; end
    v = sort(v(:)');
    starts = [1, find(diff(v) > 1) + 1];
    ends   = [starts(2:end) - 1, numel(v)];
    parts = cell(1, numel(starts));
    for i = 1:numel(starts)
        if starts(i) == ends(i)
            parts{i} = sprintf('%d', v(starts(i)));
        else
            parts{i} = sprintf('%d-%d', v(starts(i)), v(ends(i)));
        end
    end
    t = strjoin(parts, ' ');
end

function m = meanOrNaN(x)
    if isempty(x), m = NaN; else, m = mean(x); end
end

function m = maxOrNaN(x)
    if isempty(x), m = NaN; else, m = max(x); end
end

function s = ternary(c, a, b)
    if c, s = a; else, s = b; end
end

function opts = fillDefaults(opts)
    defaults = struct('duration', Inf, 'messageInterval', 5, 'showDisplay', true, ...
                      'showHopDisplay', true, 'printEachSlot', true, 'minPacketsPerSlot', 1, ...
                      'adaptive', true, 'surveyVisits', 2, 'minPassRate', 0.5, ...
                      'minPacketRate', 0.5, 'minChannels', 25, ...
                      'framesPerBlock', 4, 'extraFrames', 12, 'maxFlushFrames', 32, ...
                      'warmupSlots', 1, ...
                      'routeMode', false, 'myId', NaN);
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(opts, names{k}) || isempty(opts.(names{k}))
            opts.(names{k}) = defaults.(names{k});
        end
    end
end
