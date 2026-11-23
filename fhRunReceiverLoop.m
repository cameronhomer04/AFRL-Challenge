function stats = fhRunReceiverLoop(cfg, fh, radioRx, opts)
% FHRUNRECEIVERLOOP  Frequency-hopping receive node: finds the transmitter,
% follows its hops and decodes its pi/4-DQPSK packets until stopped.
%
%   stats = fhRunReceiverLoop(cfg, fh, radioRx, opts)
%
%   cfg     - settings from qpskConfig (the modem)
%   fh      - struct from fhConfig plus slotGuard / pktGap / allowed (see
%             runNode_FH); MUST match the transmitter (fc, channels, dwell,
%             key, guard, gap, excluded channels)
%   radioRx - comm.SDRuReceiver (sdr.rx from setupSdrNode)
%   opts    - struct, any field may be left out:
%       framesPerBlock  frames captured and decoded per pass (default 4)
%       maxFlushFrames  0 if the receiver is in burst mode (default),
%                       otherwise stale frames to discard per pass, e.g. 32
%       duration        seconds to run after the radio has started;
%                       Inf = until Stop / Ctrl+C (default)
%       showDisplay     open the live window (default true)
%       acquire         'scan' (default): while searching, move to the next
%                       channel every scanBlocks blocks, so the transmitter
%                       is found within about (channels x scanBlocks) blocks.
%                       'park': stay on the channel of slot 0 (the old
%                       behaviour; can take up to 2 x channels x dwell).
%       scanBlocks      blocks on each channel while scanning (default 1)
%       lostAfterSlots  slots with no good packet before the lock is
%                       dropped and scanning starts again (default 4)
%       maxDrainBlocks  most queued (old) blocks thrown away before each
%                       decode to reach live samples (default 200)
%       routeMode       true if every payload starts with an A* routing
%                       number (fhAddRoute); the route and the forwarding
%                       decision are printed with each new message (default false)
%       myId            this node's SDR ID in the A* SDR bank (default NaN)
%       strictNextHop   (needs routeMode and myId) true: accept a message only
%                       when myId is FIRST in its route, i.e. after the node in
%                       front of this one has relayed it (senders and repeaters
%                       remove their own ID). Packets for another node are
%                       ignored completely, including for following the hops,
%                       so the receiver keeps scanning past a sender that is
%                       still on air until it finds the relay's burst.
%                       false (default): accept every packet heard.%       rxLatency       seconds between the radio sampling a block and
%                       MATLAB receiving it (default 0). Raise it a few ms if
%                       the receiver keeps reaching new channels late.
%
%   stats - counts of decoded / failed / missed packets, hops followed,
%           locks gained / lost, time to first lock, the measured slot
%           length, messages ignored by strictNextHop, and a log of
%           messages received with times
%
% How it follows the transmitter (see fhRxFollow):
%   Acquiring: scans the channels (or parks on one). A good packet header
%     gives the slot number and the packet number in the slot, which pin
%     down the hop sequence and the slot timing. The channel the packet was
%     heard on does not matter, so a scan locks as soon as it lands on the
%     transmitter's channel for one block.
%   Locked: before each block the receiver tunes to the channel the
%     transmitter will be on for most of that block. The slot length is
%     MEASURED from the packets heard (a transmitter that underruns makes
%     every slot a little longer than the dwell), so the prediction does
%     not drift between packets.
%   Lost: after lostAfterSlots slots with no good header it scans again.
% The radio is released when this returns, including after Ctrl+C.

    if nargin < 4, opts = struct(); end
    opts = fillDefaults(opts);
    if ~isfield(fh, 'allowed') || isempty(fh.allowed)
        fh.allowed = 1:fh.nCh;
    end
    nAllowed = numel(fh.allowed);

    strict = opts.strictNextHop && opts.routeMode && ~isnan(opts.myId);
    if opts.strictNextHop && ~strict
        warning(['strictNextHop needs routeMode = true and myId set; it is OFF ' ...
                 'for this run (every packet is accepted).']);
    end

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
    scanning = strcmpi(opts.acquire, 'scan');

    cleanup = onCleanup(@() release(radioRx)); %#ok<NASGU>  % runs on return, error or Ctrl+C

    % ---- Start the radio before the clock starts (first call loads it: seconds) ----
    fprintf('\nStarting the receiver...\n');
    % The live window is created FIRST: once the radio streams, any pause
    % (a figure takes a second or more to appear) leaves old samples queued.
    display = [];
    if opts.showDisplay
        display = createLiveRxDisplay(cfg);
        stopHint = 'Press Stop in the live window (or Ctrl+C) to end.';
    else
        stopHint = 'Press Ctrl+C to end.';
    end
    tStart = tic;
    captureBlock(radioRx, opts.framesPerBlock, opts.maxFlushFrames);
    fprintf('Receiver running after %.1f s.\n', toc(tStart));

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
    stats.timeToLock      = NaN;         % s from start to the first lock
    stats.blocksDrained   = 0;           % old blocks thrown away to reach live samples
    stats.oldSamplePkts   = 0;           % packets from a channel the radio had already left
    stats.ignoredPkts     = 0;           % good packets whose message strictNextHop ignored
    stats.log = struct('time', {}, 'slot', {}, 'channel', {}, 'hexMessage', {});
    metricHistory = zeros(0, 1);
    firstSlot = NaN; lastSlot = NaN;

    st = fhRxFollow([], fh);              % starts acquiring
    st.lostAfter = opts.lostAfterSlots;
    period = fh.dwell;                    % measured slot length (s), starts at the dwell
    anchors = zeros(0, 2);                % [slot, slot start time] of recent good packets
    scanIdx = 0;

    fprintf('Hop-following receiver: %d samples (%.1f ms) per block. %s\n', ...
            blockSamples, 1e3*blockSec, stopHint);
    if strict
        fprintf(['Next-hop filter STRICT (demo): a message is accepted only when SDR %d is ' ...
                 'first in its route,\n  i.e. after the node before it has relayed it.\n'], opts.myId);
    elseif opts.routeMode
        fprintf('Next-hop filter OFF: every packet heard is accepted.\n');
    end
    if scanning
        fprintf('Acquiring: scanning %d channels, %d block(s) on each.\n', nAllowed, opts.scanBlocks);
    else
        fprintf(['Acquiring: parked on channel %d (%.3f MHz). The transmitter comes by within ' ...
                 '%.1f s, up to twice that if slot 0 was missed.\n'], ...
                st.parkCh, fh.freqs(st.parkCh)/1e6, nAllowed * fh.dwell);
    end

    lastMessage = '';
    lastIgnored = '';
    lastSummary = 0;
    runTimer = tic;

    while toc(runTimer) < opts.duration
        % ---- Pick the channel for the coming block ----
        if st.locked
            tAhead = toc(st.t0) + lead;
            slotAhead = st.refSlot + floor((tAhead - st.refStart) / period);
            ch = fhHopSequence(fh, slotAhead);
        elseif scanning
            ch = fh.allowed(mod(floor(scanIdx / opts.scanBlocks), nAllowed) + 1);
            scanIdx = scanIdx + 1;
            slotAhead = NaN;
        else
            ch = st.parkCh;
            slotAhead = NaN;
        end
        [~, retuned] = fhTune(radioRx, fh, ch);
        stats.retunes = stats.retunes + retuned;

        % ---- Capture one LIVE block and decode it ----
        % A block that arrives at once was already queued, so it is old:
        % throw it away and read again until a read has to wait for samples.
        % Following the hops needs to know WHEN each sample was taken; old
        % samples make every prediction late and the lock is lost.
        [block, overflowed, nOld] = captureLive(radioRx, opts, blockSec);
        tBlockEnd = toc(st.t0) - opts.rxLatency;
        stats.blocksDrained = stats.blocksDrained + nOld;
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
                stats.packetsOK = stats.packetsOK + 1;
                state = 'packet OK';
                if fhHopSequence(fh, slot) ~= ch
                    stats.oldSamplePkts = stats.oldSamplePkts + 1;   % taken before the last retune
                end
                payload = rx.hexMessage(13:end);

                % ---- Next-hop filter (demo switch) ----
                % A packet for another node is NOT used to follow the hops:
                % locking onto the original sender (still on air) would keep
                % this receiver away from the relay's burst.
                accept = true;
                if strict
                    [~, ~, okRoute, ids] = fhSplitRoute(payload);
                    accept = okRoute && ~isempty(ids) && ids(1) == opts.myId;
                end
            end
            if ok && ~accept
                stats.ignoredPkts = stats.ignoredPkts + 1;
                state = 'packet OK, not for me yet (ignored)';
                if ~strcmp(payload, lastIgnored)              % print once per payload
                    lastIgnored = payload;
                    if okRoute && ~isempty(ids)
                        fprintf(['[%7.1f s] Ignored: %s   (route %s, next hop is SDR %d, not ' ...
                                 'SDR %d: waiting for the relay)\n'], toc(runTimer), payload, ...
                                idText(ids), ids(1), opts.myId);
                    else
                        fprintf('[%7.1f s] Ignored: %s   (no readable route)\n', ...
                                toc(runTimer), payload);
                    end
                end
            elseif ok
                gotHeader = true;

                % When did this packet's slot start (receiver clock)?
                lay = fhPacketLayout(cfg, fh, rx.numHexChars);
                pktStartSample = rx.sync.preambleStartSample - cfg.filterSpan*cfg.samplesPerSymbol;
                tPkt = tBlockEnd - (numel(block) - pktStartSample + 1) / fs;
                tSlotStart = tPkt - (lay.leadSamples + k*lay.pktStep) / fs;
                st = fhRxFollow(st, fh, slot, 0, 1, tSlotStart + 0.5*fh.dwell);

                % Measure the real slot length from the recent slot starts
                [anchors, period] = updatePeriod(anchors, slot, tSlotStart, fh.dwell, period);

                if isnan(lastSlot) || slot ~= lastSlot
                    stats.slotsHeard = stats.slotsHeard + 1;
                end
                if isnan(firstSlot), firstSlot = slot; end
                lastSlot = slot;

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
            if isnan(stats.timeToLock), stats.timeToLock = toc(runTimer); end
            fprintf('[%7.1f s] Locked to the transmitter at slot %d.\n', toc(runTimer), st.refSlot);
        elseif wasLocked && ~st.locked
            stats.locksLost = stats.locksLost + 1;
            anchors = zeros(0, 2);                            % keep the measured period
            if scanning
                fprintf('[%7.1f s] Lost the transmitter after slot %d; scanning again.\n', ...
                        toc(runTimer), st.refSlot);
            else
                fprintf('[%7.1f s] Lost the transmitter after slot %d; parking on channel %d again.\n', ...
                        toc(runTimer), st.refSlot, st.parkCh);
            end
        end

        % ---- Report ----
        statusLines = makeStatusLines(stats, rx, state, lastMessage, st, ch, slotAhead, fh, ...
                                      firstSlot, lastSlot, scanning, period, strict);
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
    stats.slotSeconds = period;
    stats.strictNextHop = strict;

    fprintf('\n--- Hop-following receive summary (%.1f s) ---\n', stats.duration);
    fprintf('Blocks: %d (%.0f ms each pass)   Packets OK: %d   Checksum failed: %d   Header failed: %d   No packet: %d\n', ...
            stats.blocks, 1e3*stats.duration/max(stats.blocks, 1), stats.packetsOK, ...
            stats.checksumFailed, stats.headerFailed, stats.noPacket);
    if strict
        fprintf('Next-hop filter STRICT: %d of %d good packets were for another node and ignored.\n', ...
                stats.ignoredPkts, stats.packetsOK);
    end
    fprintf('Retunes: %d   Locks gained: %d   Locks lost: %d   First lock after %.1f s\n', ...
            stats.retunes, stats.locksGained, stats.locksLost, stats.timeToLock);
    if ~isnan(firstSlot)
        fprintf('Hops heard: %d of %d between slot %d and slot %d (%.0f%%)\n', ...
                stats.slotsHeard, lastSlot - firstSlot + 1, firstSlot, lastSlot, 100*stats.hopFraction);
        fprintf('Measured slot length: %.4f s (dwell %.4f s)', period, fh.dwell);
        if period > 1.01 * fh.dwell
            fprintf(' -> the transmitter''s slots run long (underruns)');
        end
        fprintf('\n');
    end
    fprintf('Blocks with RX overflow: %d   Decode errors: %d\n', ...
            stats.overflowBlocks, stats.decodeErrors);
    fprintf('Old blocks thrown away: %d   Packets from a channel already left (old samples): %d of %d\n', ...
            stats.blocksDrained, stats.oldSamplePkts, stats.packetsOK);
    if stats.packetsOK > 0 && stats.oldSamplePkts > 0.2 * stats.packetsOK
        fprintf(['  Many packets came from before the last retune: samples reach MATLAB late.\n' ...
                 '  Turn off showPlots, or raise rxLatency (s) in runNode_FH.\n']);
    end
    fprintf('Radio released.\n');
end

% ======================================================================
function [block, overflowed, nOld] = captureLive(radioRx, opts, blockSec)
% Read blocks until one takes at least half its own length to arrive,
% which means the radio was producing it in real time. Blocks that arrive
% at once had been waiting in the buffer and are thrown away. Whole blocks
% are read, so burst mode stays aligned.
    overflowed = false;
    nOld = 0;
    for i = 1:opts.maxDrainBlocks
        t = tic;
        [block, ov] = captureBlock(radioRx, opts.framesPerBlock, opts.maxFlushFrames);
        overflowed = overflowed || ov;
        if toc(t) >= 0.5 * blockSec
            return;                                   % live
        end
        nOld = nOld + 1;
    end
end

function [anchors, period] = updatePeriod(anchors, slot, tStart, dwell, period)
% Least-squares fit of slot start time against slot number over the last
% 30 slots. Needs packets from at least 3 different slots; the result is
% kept within 0.7-2 x dwell so a bad estimate cannot run away.
    anchors(end+1, :) = [slot, tStart];
    anchors = anchors(anchors(:,1) >= slot - 30 & anchors(:,1) <= slot, :);
    if numel(unique(anchors(:,1))) >= 3
        s = anchors(:,1) - mean(anchors(:,1));
        t = anchors(:,2) - mean(anchors(:,2));
        p = sum(s .* t) / sum(s .^ 2);
        period = min(max(p, 0.7*dwell), 2*dwell);
    end
end

function f = hopFraction(stats, firstSlot, lastSlot)
    if isnan(firstSlot)
        f = 0;
    else
        f = stats.slotsHeard / max(lastSlot - firstSlot + 1, 1);
    end
end

function lines = makeStatusLines(stats, rx, state, lastMessage, st, ch, slotAhead, fh, ...
                                 firstSlot, lastSlot, scanning, period, strict)
    if isempty(lastMessage)
        shownMessage = '(none yet)';
    else
        shownMessage = lastMessage;
    end
    if st.locked
        hopText = sprintf('LOCKED  slot %d  ch %d (%.3f MHz)', slotAhead, ch, fh.freqs(ch)/1e6);
    elseif scanning
        hopText = sprintf('SCANNING  ch %d (%.3f MHz)', ch, fh.freqs(ch)/1e6);
    else
        hopText = sprintf('ACQUIRING  parked on ch %d (%.3f MHz)', ch, fh.freqs(ch)/1e6);
    end
    lines{1} = sprintf('%s   |   Last message: %s   |   This block: %s', hopText, shownMessage, state);
    lines{2} = sprintf(['OK %d  |  checksum failed %d  |  header failed %d  |  no packet %d  |  ' ...
                        'blocks %d  |  overflows %d'], stats.packetsOK, stats.checksumFailed, ...
                        stats.headerFailed, stats.noPacket, stats.blocks, stats.overflowBlocks);
    if strict
        lines{2} = sprintf('%s  |  STRICT next hop: ignored %d', lines{2}, stats.ignoredPkts);
    end
    if isnan(rx.freqOffsetHz)
        offsetText = '-';
    else
        offsetText = sprintf('%.0f Hz', rx.freqOffsetHz);
    end
    lines{3} = sprintf('Level %.1f dBFS peak  |  metric %.2f  |  offset %s  |  slot %.3f s', ...
                       rx.peakDbfs, rx.sync.metric, offsetText, period);
    if ~isnan(firstSlot)
        lines{3} = sprintf('%s  |  hops heard %d of %d', lines{3}, stats.slotsHeard, ...
                           lastSlot - firstSlot + 1);
    end
end

function printRoute(payload, myId)
% Show the A* route carried in the payload and where this node is on it.
% The route comes only from the packet: the receiver needs no route file.
    [routeHex, msg, ok, sdrList] = fhSplitRoute(payload);
    if ~ok
        fprintf('           No valid A* route in this payload.\n');
        return;
    end
    if isempty(msg), msg = '(none)'; end
    fprintf('           Route %s -> SDRs %s   message %s\n', routeHex, mat2str(sdrList(:)'), msg);
    if ~isnan(myId)
        pos = find(sdrList == myId, 1);
        if isempty(pos)
            fprintf('           This node (SDR %d) is NOT on the route.\n', myId);
        elseif pos == 1 && numel(sdrList) == 1
            fprintf('           This node (SDR %d) is the destination: delivered.\n', myId);
        elseif pos == 1
            fprintf('           This node (SDR %d) is the next hop.\n', myId);
        else
            fprintf(['           This node (SDR %d) is on the route, but SDR(s) %s come first: ' ...
                     'heard directly, relay(s) skipped.\n'], myId, idText(sdrList(1:pos-1)));
        end
    end
end

function t = idText(ids)
    t = strjoin(arrayfun(@num2str, ids(:)', 'UniformOutput', false), ' -> ');
end

function opts = fillDefaults(opts)
    defaults = struct('framesPerBlock', 4, 'maxFlushFrames', 0, 'duration', Inf, ...
                      'showDisplay', true, 'rxLatency', 0, 'routeMode', false, 'myId', NaN, ...
                      'strictNextHop', false, ...
                      'acquire', 'scan', 'scanBlocks', 1, ...
                      'lostAfterSlots', 4, 'maxDrainBlocks', 200);
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(opts, names{k}) || isempty(opts.(names{k}))
            opts.(names{k}) = defaults.(names{k});
        end
    end
end
