function stats = fhRunReceiverLoop(cfg, fh, radioRx, opts)
% FHRUNRECEIVERLOOP  Frequency-hopping receive node: finds the transmitter,
% follows its hops and decodes its pi/4-DQPSK packets until stopped.
%
%   stats = fhRunReceiverLoop(cfg, fh, radioRx, opts)
%
%   cfg     - settings from qpskConfig (the modem)
%   fh      - struct from fhConfig plus slotGuard / pktGap (see runNode_FH);
%             MUST match the transmitter (fc, channels, dwell, key, guard, gap)
%   radioRx - comm.SDRuReceiver (sdr.rx from setupSdrNode)
%   opts    - struct, any field may be left out:
%       framesPerBlock  frames captured and decoded per pass (default 4)
%       maxFlushFrames  0 if the receiver is in burst mode (default),
%                       otherwise stale frames to discard per pass, e.g. 32
%       duration        seconds to run; Inf = until Stop / Ctrl+C (default)
%       showDisplay     open the live window (default true)
%       routeMode       true if every payload starts with an A* routing
%                       number (fhAddRoute); the route and the forwarding
%                       decision are printed with each new message (default false)
%       myId            this node's SDR ID in the A* SDR bank (default NaN)
%       rxLatency       seconds between the radio sampling a block and
%                       MATLAB receiving it (default 0). Raise it a few ms if
%                       the receiver keeps reaching new channels late.
%
%   stats - counts of decoded / failed / missed packets, hops followed,
%           locks gained / lost, and a log of messages received with times
%
% How it follows the transmitter (see fhRxFollow):
%   Acquiring: parks on one channel. The transmitter visits every channel
%     once per nCh slots, so it is heard within nCh x dwell seconds.
%   Locked: every good packet header gives the slot number and the packet
%     number in the slot; with fhPacketLayout that pins down when the slot
%     started. Before each block the receiver tunes to the channel the
%     transmitter will be on for most of that block.
%   Lost: after 3 slots with no good header it goes back to acquiring.
% The radio is released when this returns, including after Ctrl+C.

    if nargin < 4, opts = struct(); end
    opts = fillDefaults(opts);

    fs = cfg.sampleRate;
    blockSamples = opts.framesPerBlock * cfg.samplesPerFrame;
    neededSamples = (2*cfg.maxPacketSymbols + 2*cfg.filterSpan + 10) * cfg.samplesPerSymbol;
    if blockSamples < neededSamples
        error('framesPerBlock = %d is too small; use at least %d so a whole packet always fits.', ...
              opts.framesPerBlock, ceil(neededSamples / cfg.samplesPerFrame));
    end
    blockSec = blockSamples / fs;
    if fh.dwell < 3 * blockSec
        warning(['Dwell (%.0f ms) is less than 3 receive blocks (%.0f ms each): ' ...
                 'many blocks will straddle a hop. Use a longer dwell or fewer frames per block.'], ...
                1e3*fh.dwell, 1e3*blockSec);
    end
    lead = 0.5 * blockSec;          % tune for the middle of the coming block

    cleanup = onCleanup(@() release(radioRx)); %#ok<NASGU>  % runs on return, error or Ctrl+C

    % ---- Statistics ----
    stats.blocks          = 0;
    stats.samplesReceived = 0;
    stats.packetsOK       = 0;
    stats.checksumFailed  = 0;
    stats.headerFailed    = 0;
    stats.noPacket        = 0;
    stats.overflowBlocks  = 0;
    stats.decodeErrors    = 0;
    stats.retunes         = 0;
    stats.locksGained     = 0;
    stats.locksLost       = 0;
    stats.slotsHeard      = 0;           % different slots with a good packet
    stats.log = struct('time', {}, 'slot', {}, 'channel', {}, 'hexMessage', {});
    metricHistory = zeros(0, 1);
    firstSlot = NaN; lastSlot = NaN;

    st = fhRxFollow([], fh);              % starts acquiring on st.parkCh

    display = [];
    if opts.showDisplay
        display = createLiveRxDisplay(cfg);
        stopHint = 'Press Stop in the live window (or Ctrl+C) to end.';
    else
        stopHint = 'Press Ctrl+C to end.';
    end
    fprintf('\nHop-following receiver: %d samples (%.1f ms) per block. %s\n', ...
            blockSamples, 1e3*blockSec, stopHint);
    fprintf('Acquiring: parked on channel %d (%.3f MHz). The transmitter comes by within %.1f s.\n', ...
            st.parkCh, fh.freqs(st.parkCh)/1e6, fh.nCh * fh.dwell);

    lastMessage = '';
    lastSummary = 0;
    runTimer = tic;

    while toc(runTimer) < opts.duration
        % ---- Pick the channel for the coming block ----
        if st.locked
            tAhead = toc(st.t0) + lead;
            slotAhead = st.refSlot + floor((tAhead - st.refStart) / fh.dwell);
            ch = fhHopSequence(fh, slotAhead);
        else
            ch = st.parkCh;
            slotAhead = NaN;
        end
        [~, retuned] = fhTune(radioRx, fh, ch);
        stats.retunes = stats.retunes + retuned;

        % ---- Capture and decode one block ----
        [block, overflowed] = captureBlock(radioRx, opts.framesPerBlock, opts.maxFlushFrames);
        tBlockEnd = toc(st.t0) - opts.rxLatency;
        stats.blocks = stats.blocks + 1;
        stats.samplesReceived = stats.samplesReceived + numel(block);
        stats.overflowBlocks = stats.overflowBlocks + overflowed;

        try
            rx = receivePacket(cfg, block);
        catch ME
            stats.decodeErrors = stats.decodeErrors + 1;
            if stats.decodeErrors == 1
                warning('Block %d could not be decoded: %s', stats.blocks, ME.message);
            end
            st = fhRxFollow(st, fh);
            continue;
        end
        metricHistory(end+1, 1) = rx.sync.metric; %#ok<AGROW>

        wasLocked = st.locked;
        gotHeader = false;
        if ~rx.detected
            stats.noPacket = stats.noPacket + 1;
            state = 'no packet';
        elseif ~rx.valid || ~rx.checksumOK
            stats.checksumFailed = stats.checksumFailed + 1;
            state = 'checksum FAILED';
        elseif rx.numHexChars < 13
            stats.headerFailed = stats.headerFailed + 1;
            state = 'too short for a hop header';
        else
            [slot, k, ok] = fhReadHeader(hexToBits(rx.hexMessage(1:12)));
            if ~ok
                stats.headerFailed = stats.headerFailed + 1;
                state = 'header CRC FAILED';
            else
                gotHeader = true;
                stats.packetsOK = stats.packetsOK + 1;
                state = 'packet OK';

                % When did this packet's slot start (receiver clock)?
                lay = fhPacketLayout(cfg, fh, rx.numHexChars);
                pktStartSample = rx.sync.preambleStartSample - cfg.filterSpan*cfg.samplesPerSymbol;
                tPkt = tBlockEnd - (numel(block) - pktStartSample + 1) / fs;
                tSlotStart = tPkt - (lay.leadSamples + k*lay.pktStep) / fs;
                st = fhRxFollow(st, fh, slot, 0, 1, tSlotStart + 0.5*fh.dwell);

                if isnan(lastSlot) || slot ~= lastSlot
                    stats.slotsHeard = stats.slotsHeard + 1;
                end
                if isnan(firstSlot), firstSlot = slot; end
                lastSlot = slot;

                payload = rx.hexMessage(13:end);
                if ~strcmp(payload, lastMessage)              % print only when it changes
                    lastMessage = payload;
                    stats.log(end+1) = struct('time', toc(runTimer), 'slot', slot, ...
                                              'channel', ch, 'hexMessage', payload);
                    fprintf('[%7.1f s] Received: %s   (slot %d, ch %d, offset %.0f Hz, metric %.2f)\n', ...
                            toc(runTimer), payload, slot, ch, rx.freqOffsetHz, rx.sync.metric);
                    if opts.routeMode
                        printRoute(payload, opts.myId);
                    end
                end
            end
        end
        if ~gotHeader
            st = fhRxFollow(st, fh);                          % nothing usable this block
        end

        % ---- Lock changes ----
        if ~wasLocked && st.locked
            stats.locksGained = stats.locksGained + 1;
            fprintf('[%7.1f s] Locked to the transmitter at slot %d.\n', toc(runTimer), st.refSlot);
        elseif wasLocked && ~st.locked
            stats.locksLost = stats.locksLost + 1;
            fprintf('[%7.1f s] Lost the transmitter; parking on channel %d again.\n', ...
                    toc(runTimer), st.parkCh);
        end

        % ---- Report ----
        statusLines = makeStatusLines(stats, rx, state, lastMessage, st, ch, slotAhead, fh, ...
                                      firstSlot, lastSlot);
        if ~isempty(display)
            if ~updateLiveRxDisplay(display, cfg, block, rx, metricHistory, statusLines)
                break;                                        % Stop pressed / window closed
            end
        elseif toc(runTimer) - lastSummary >= 5
            lastSummary = toc(runTimer);
            fprintf('[%7.1f s] %s\n', lastSummary, statusLines{2});
        end
    end

    stats.duration = toc(runTimer);
    stats.metricHistory = metricHistory;
    stats.firstSlot = firstSlot;
    stats.lastSlot = lastSlot;
    stats.hopFraction = hopFraction(stats, firstSlot, lastSlot);

    fprintf('\n--- Hop-following receive summary (%.1f s) ---\n', stats.duration);
    fprintf('Blocks: %d   Packets OK: %d   Checksum failed: %d   Header failed: %d   No packet: %d\n', ...
            stats.blocks, stats.packetsOK, stats.checksumFailed, stats.headerFailed, stats.noPacket);
    fprintf('Retunes: %d   Locks gained: %d   Locks lost: %d\n', ...
            stats.retunes, stats.locksGained, stats.locksLost);
    if ~isnan(firstSlot)
        fprintf('Hops heard: %d of %d between slot %d and slot %d (%.0f%%)\n', ...
                stats.slotsHeard, lastSlot - firstSlot + 1, firstSlot, lastSlot, 100*stats.hopFraction);
    end
    fprintf('Blocks with RX overflow: %d   Decode errors: %d\n', ...
            stats.overflowBlocks, stats.decodeErrors);
    fprintf('Radio released.\n');
end

% ======================================================================
function f = hopFraction(stats, firstSlot, lastSlot)
    if isnan(firstSlot)
        f = 0;
    else
        f = stats.slotsHeard / max(lastSlot - firstSlot + 1, 1);
    end
end

function lines = makeStatusLines(stats, rx, state, lastMessage, st, ch, slotAhead, fh, firstSlot, lastSlot)
    if isempty(lastMessage)
        shownMessage = '(none yet)';
    else
        shownMessage = lastMessage;
    end
    if st.locked
        hopText = sprintf('LOCKED  slot %d  ch %d (%.3f MHz)', slotAhead, ch, fh.freqs(ch)/1e6);
    else
        hopText = sprintf('ACQUIRING  parked on ch %d (%.3f MHz)', ch, fh.freqs(ch)/1e6);
    end
    lines{1} = sprintf('%s   |   Last message: %s   |   This block: %s', hopText, shownMessage, state);
    lines{2} = sprintf(['OK %d  |  checksum failed %d  |  header failed %d  |  no packet %d  |  ' ...
                        'blocks %d  |  overflows %d'], stats.packetsOK, stats.checksumFailed, ...
                        stats.headerFailed, stats.noPacket, stats.blocks, stats.overflowBlocks);
    if isnan(rx.freqOffsetHz)
        offsetText = '-';
    else
        offsetText = sprintf('%.0f Hz', rx.freqOffsetHz);
    end
    lines{3} = sprintf('Level %.1f dBFS peak  |  metric %.2f  |  offset %s', ...
                       rx.peakDbfs, rx.sync.metric, offsetText);
    if ~isnan(firstSlot)
        lines{3} = sprintf('%s  |  hops heard %d of %d', lines{3}, stats.slotsHeard, ...
                           lastSlot - firstSlot + 1);
    end
end

function printRoute(payload, myId)
% Show the A* route carried in the payload and what this node would do.
    [routeHex, msg, ok, sdrList] = fhSplitRoute(payload);
    if ~ok
        fprintf('           No valid A* route in this payload.\n');
        return;
    end
    if isempty(msg), msg = '(none)'; end
    fprintf('           Route %s -> SDRs %s   message %s\n', routeHex, mat2str(sdrList(:)'), msg);
    if ~isnan(myId)
        if any(sdrList == myId)
            fprintf('           This node (SDR %d) IS on the route: forward.\n', myId);
        else
            fprintf('           This node (SDR %d) is NOT on the route: ignore.\n', myId);
        end
    end
end

function opts = fillDefaults(opts)
    defaults = struct('framesPerBlock', 4, 'maxFlushFrames', 0, 'duration', Inf, ...
                      'showDisplay', true, 'rxLatency', 0, 'routeMode', false, 'myId', NaN);
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(opts, names{k}) || isempty(opts.(names{k}))
            opts.(names{k}) = defaults.(names{k});
        end
    end
end
