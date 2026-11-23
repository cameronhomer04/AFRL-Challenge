function stats = fhRunRepeater(cfg, fh, sdr, opts)
% FHRUNREPEATER  Mesh repeater: listens for hopping bursts and passes each
% alert one step further along its A* route.
%
%   stats = fhRunRepeater(cfg, fh, sdr, opts)
%
%   cfg  - settings from qpskConfig (the modem)
%   fh   - struct from fhConfig plus slotGuard / pktGap / allowed (see
%          runNode_FH); MUST match every other node
%   sdr  - node from setupSdrNode with role "repeater" (tx and rx objects,
%          receiver NOT in burst mode). Both stay open for the whole run.
%   opts - struct, any field may be left out unless marked required:
%       myId           this node's SDR ID (required)
%       burstSlots     slots in every burst, the same on every node (required;
%                      runNode_FH sets it from burstSeconds)
%       originate      payload this node raises itself, [ LL | route | message ]
%                      from fhAddRoute, or '' to only relay (default '')
%       strictNextHop  true (default): act on a burst only when myId is FIRST
%                      in its route (the demo rule: the message must come
%                      through every relay in turn). false: act when myId is
%                      ANYWHERE in the route, skipping the IDs in front of it
%                      (a node that hears the sender directly takes it).
%       duration       seconds to run; Inf = until Ctrl+C (default Inf)
%       framesPerBlock frames captured and decoded per pass (default 4)
%       maxFlushFrames stale RX frames thrown away before each block (default 32)
%       txGuard        extra wait after the incoming burst ends before this
%                      node starts its own burst, in s (default 0.2)
%       rxLatency      seconds between the radio sampling a block and
%                      MATLAB receiving it (default 0)
%
%   stats - counts, plus
%       eventLog  struct of column vectors, ONE ROW PER EVENT:
%                 time (when the node decided; a burst then follows), event ('originated', 'forwarded', 'delivered',
%                 'duplicate', 'ignored', 'unordered', 'invalid', 'notSent'), slot heard,
%                 routeIn, routeOut, nextId, message, underruns
%                 Turn it into a table with struct2table(stats.eventLog).
%       delivered cell array of the messages this node kept as destination
%       bursts    one entry per burst sent: tStart, tEnd, channels, kind, nextId
%       pktTimes, badTimes  times of good packets / checksum failures
%       Draw them with fhRepeaterSummary(stats, fh) (runNode_FH does this
%       at the end when showPlots is true).
%
% Every node runs one rule on every message (fhNextHop):
%   1. Act on the first good packet of a burst; ignore the rest of that burst.
%   2. If the first ID in the route is not mine, ignore the message.
%      (strictNextHop = false: ignore it only if my ID is not in the route.)
%   3. Remove my ID (and any skipped IDs in front of it) from the route.
%   4. If the route is now empty, I am the destination: keep the message.
%   5. Otherwise wait for the incoming burst to end. Every burst starts at
%      slot 0 and lasts burstSlots slots, so a node that read slot k at a
%      known time waits (burstSlots - k) x dwell from the start of slot k,
%      plus txGuard.
%   6. Send my own burst (slots 0 .. burstSlots-1) with the shortened route.
% The originator passes its own payload through the same rule (always
% strict) with a zero wait. If the first ID on its route is not myId it
% warns and sends nothing.
%
% With strictNextHop = false the destination may take the message straight
% from the originator AND again from the relay; the second copy is logged
% as 'duplicate' and not counted again.
%
% Listening: the node parks on the channel of slot 0. Every burst starts
% there, so an idle node hears slot 0. The hop order changes every pass
% through the channels, so that channel comes round again somewhere
% between slot n+1 and slot 2n-1 (n = channels in use); a burst that
% reaches it (burstSeconds = "auto" in runNode_FH) gives a node that
% missed slot 0 a second chance. No hop following is needed because one
% good packet is enough.
%
% While transmitting (and while waiting to transmit) the node hears
% nothing; the RX reports overflows then, which is expected. Hearing the
% next node's burst afterwards ("for SDR n: not mine") shows the alert
% moved on, but it is not a delivery confirmation.

    if nargin < 4, opts = struct(); end
    opts = fillDefaults(opts);
    if isempty(sdr.tx) || isempty(sdr.rx)
        error('fhRunRepeater needs a node with a transmitter and a receiver (role "repeater").');
    end
    if isnan(opts.myId)
        error('fhRunRepeater: set opts.myId to this node''s SDR ID.');
    end
    if isnan(opts.burstSlots) || opts.burstSlots < 1
        error('fhRunRepeater: set opts.burstSlots (runNode_FH sets it from burstSeconds).');
    end
    if ~isfield(fh, 'allowed') || isempty(fh.allowed)
        fh.allowed = 1:fh.nCh;
    end
    N = opts.burstSlots;
    nAllowed = numel(fh.allowed);
    parkSeq = fhHopSequence(fh, 0 : 2*nAllowed - 1);
    secondVisit = find(parkSeq(2:end) == parkSeq(1), 1);
    if N <= secondVisit
        warning(['A burst of %d slots ends before the listening channel comes round again ' ...
                 '(slot %d): a node that misses slot 0 will not hear it. ' ...
                 'Use burstSeconds = "auto" or at least %.1f s.'], ...
                N, secondVisit, (secondVisit + 1) * fh.dwell + 0.5);
    end

    fs = cfg.sampleRate;
    blockSamples = opts.framesPerBlock * cfg.samplesPerFrame;
    neededSamples = (2*cfg.maxPacketSymbols + 2*cfg.filterSpan + 10) * cfg.samplesPerSymbol;
    if blockSamples < neededSamples
        error('framesPerBlock = %d is too small; use at least %d so a whole packet always fits.', ...
              opts.framesPerBlock, ceil(neededSamples / cfg.samplesPerFrame));
    end

    cleanup = onCleanup(@() releaseSdrNode(sdr)); %#ok<NASGU>  % runs on return, error or Ctrl+C

    % ---- Statistics ----
    stats.blocks = 0; stats.packetsOK = 0; stats.checksumFailed = 0;
    stats.headerFailed = 0; stats.noPacket = 0; stats.decodeErrors = 0;
    stats.notBurst = 0; stats.overflowBlocks = 0;
    stats.originated = 0; stats.forwarded = 0; stats.delivered = {};
    stats.ignored = 0; stats.duplicates = 0; stats.underruns = 0;
    stats.bursts = struct('tStart', {}, 'tEnd', {}, 'channels', {}, 'kind', {}, 'nextId', {});
    stats.pktTimes = zeros(0, 1);             % time of every good packet (for the summary figure)
    stats.badTimes = zeros(0, 1);             % time of every checksum failure
    L = emptyLog();

    parkCh = fhHopSequence(fh, 0);
    fhTune(sdr.rx, fh, parkCh);
    t0 = tic;

    % Start the transmitter now: its first call loads the radio (seconds),
    % which must not delay the first burst. Silence, so nothing goes on air.
    fhTune(sdr.tx, fh, parkCh);
    stats.underruns = stats.underruns + double(sdr.tx(complex(zeros(cfg.samplesPerFrame, 1, 'single'))));

    fprintf('\nRepeater SDR %d: bursts of %d slots (%.1f s) over %d channels, %.0f ms dwell.\n', ...
            opts.myId, N, N*fh.dwell, nAllowed, 1e3*fh.dwell);
    if opts.strictNextHop
        fprintf('Next-hop filter STRICT (demo): acts only on bursts where SDR %d is first in the route.\n', ...
                opts.myId);
    else
        fprintf('Next-hop filter OFF: acts on any burst whose route lists SDR %d (relays may be skipped).\n', ...
                opts.myId);
    end

    holdPayload = '';  holdUntil = -Inf;      % rule 1: the burst already handled
    lastSent = '';     sentUntil = -Inf;      % my own burst, heard back afterwards
    deliveredMsg = ''; deliveredUntil = -Inf; % the message last kept here (duplicates)

    % ---- Originate: same rule (always strict), zero wait ----
    if ~isempty(opts.originate)
        hop = fhNextHop(opts.originate, opts.myId, true);
        switch hop.action
            case 'forward'
                tDecided = toc(t0);
                fprintf('[%7.1f s] ALERT raised: message %s, hop order %s\n', toc(t0), ...
                        hop.message, idText(hop.idsIn));
                fprintf('           Sending my burst to SDR %d (route %s -> %s).\n', ...
                        hop.nextId, hop.routeIn, hop.routeOut);
                frames = buildBurst(cfg, fh, hop.payloadOut, N);
                tB = toc(t0);
                nU = sendBurst(fh, sdr.tx, frames);
                stats.bursts(end+1) = struct('tStart', tB, 'tEnd', toc(t0), ...
                    'channels', fhHopSequence(fh, 0:N-1), 'kind', 'originated', 'nextId', hop.nextId);
                stats.underruns = stats.underruns + nU;
                stats.originated = stats.originated + 1;
                lastSent = hop.payloadOut; sentUntil = toc(t0) + N*fh.dwell;
                fprintf('[%7.1f s] Burst sent (%d underruns).\n', toc(t0), nU);
                L = appendLog(L, tDecided, 'originated', NaN, hop.routeIn, hop.routeOut, ...
                              hop.nextId, hop.message, nU);
            case 'destination'
                fprintf('[%7.1f s] The route lists only this node (SDR %d): nothing to send. Message %s kept.\n', ...
                        toc(t0), opts.myId, hop.message);
                stats.delivered{end+1} = hop.message;
                L = appendLog(L, toc(t0), 'delivered', NaN, hop.routeIn, '', NaN, hop.message, 0);
            case 'notMine'
                warning(['The route starts with SDR %d but this node is SDR %d, so the alert was ' ...
                         'NOT sent. Is route_hex.mat stale, or myId wrong? Hop order: %s'], ...
                        hop.idsIn(1), opts.myId, idText(hop.idsIn));
                L = appendLog(L, toc(t0), 'notSent', NaN, hop.routeIn, '', NaN, hop.message, 0);
            case 'unordered'
                warning(['Route %s is a bitmask or sorted list, so the hop order is unknown and the ' ...
                         'alert was NOT sent. Re-run the A* script to save an ordered route.'], hop.routeIn);
                L = appendLog(L, toc(t0), 'notSent', NaN, hop.routeIn, '', NaN, hop.message, 0);
            otherwise
                warning('The payload to originate has no readable route; nothing was sent.');
                L = appendLog(L, toc(t0), 'notSent', NaN, '', '', NaN, '', 0);
        end
    end

    fprintf('[%7.1f s] Listening on channel %d (%.3f MHz), the channel every burst starts on. Ctrl+C to end.\n', ...
            toc(t0), parkCh, fh.freqs(parkCh)/1e6);
    warnedNotBurst = false;
    lastSummary = toc(t0);

    % ---- Listen ----
    while toc(t0) < opts.duration
        [block, overflowed] = captureBlock(sdr.rx, opts.framesPerBlock, opts.maxFlushFrames);
        tBlockEnd = toc(t0) - opts.rxLatency;
        stats.blocks = stats.blocks + 1;
        stats.overflowBlocks = stats.overflowBlocks + overflowed;

        if toc(t0) - lastSummary >= 30
            lastSummary = toc(t0);
            fprintf('[%7.1f s] Listening: %d packets OK, %d checksum failed, %d forwarded, %d delivered.\n', ...
                    lastSummary, stats.packetsOK, stats.checksumFailed, stats.forwarded, ...
                    numel(stats.delivered));
        end

        try
            rx = receivePacket(cfg, block);
        catch ME
            stats.decodeErrors = stats.decodeErrors + 1;
            if stats.decodeErrors == 1
                warning('Block %d could not be decoded: %s', stats.blocks, ME.message);
            end
            continue;
        end
        if ~rx.detected
            stats.noPacket = stats.noPacket + 1;
            continue;
        end
        if ~rx.valid || ~rx.checksumOK
            stats.checksumFailed = stats.checksumFailed + 1;
            stats.badTimes(end+1, 1) = toc(t0);
            continue;
        end
        if rx.numHexChars < 13
            stats.headerFailed = stats.headerFailed + 1;
            continue;
        end
        [slot, k, ok] = fhReadHeader(hexToBits(rx.hexMessage(1:12)));
        if ~ok
            stats.headerFailed = stats.headerFailed + 1;
            continue;
        end
        stats.packetsOK = stats.packetsOK + 1;
        stats.pktTimes(end+1, 1) = toc(t0);
        payload = rx.hexMessage(13:end);

        if slot >= N
            stats.notBurst = stats.notBurst + 1;
            if ~warnedNotBurst
                warnedNotBurst = true;
                fprintf(['[%7.1f s] Heard slot %d, past the end of a %d-slot burst: a "tx" node ' ...
                         'running continuously, or a different burstSeconds. Ignored.\n'], ...
                        toc(t0), slot, N);
            end
            continue;
        end

        % When did this packet's slot start, and when does its burst end?
        lay = fhPacketLayout(cfg, fh, rx.numHexChars);
        pktStartSample = rx.sync.preambleStartSample - cfg.filterSpan*cfg.samplesPerSymbol;
        tPkt = tBlockEnd - (numel(block) - pktStartSample + 1) / fs;
        tSlotStart = tPkt - (lay.leadSamples + k*lay.pktStep) / fs;
        burstEnd = tSlotStart + (N - slot) * fh.dwell;

        % Rule 1: one action per burst
        if strcmp(payload, holdPayload) && toc(t0) < holdUntil
            continue;
        end
        if strcmp(payload, lastSent) && toc(t0) < sentUntil + N*fh.dwell
            continue;                                   % my own burst, heard back
        end
        holdPayload = payload;
        holdUntil = burstEnd + N*fh.dwell;              % rest of the burst, with margin

        hop = fhNextHop(payload, opts.myId, opts.strictNextHop);
        switch hop.action
            case 'forward'
                tDecided = toc(t0);
                fprintf('[%7.1f s] Burst for me (slot %d, packet %d): message %s\n', ...
                        toc(t0), slot, k, hop.message);
                if ~isempty(hop.skipped)
                    fprintf('           Shortcut: heard directly, skipping SDR(s) %s.\n', ...
                            idText(hop.skipped));
                end
                % Build first, then wait out the rest of the incoming burst (rule 5)
                frames = buildBurst(cfg, fh, hop.payloadOut, N);
                waitSec = burstEnd + opts.txGuard - toc(t0);
                fprintf('           Forwarding to SDR %d in %.2f s (route %s -> %s).\n', ...
                        hop.nextId, max(waitSec, 0), hop.routeIn, hop.routeOut);
                if waitSec > 0
                    pause(waitSec);
                end
                tB = toc(t0);
                nU = sendBurst(fh, sdr.tx, frames);
                stats.bursts(end+1) = struct('tStart', tB, 'tEnd', toc(t0), ...
                    'channels', fhHopSequence(fh, 0:N-1), 'kind', 'forwarded', 'nextId', hop.nextId);
                stats.underruns = stats.underruns + nU;
                stats.forwarded = stats.forwarded + 1;
                lastSent = hop.payloadOut; sentUntil = toc(t0);
                fprintf('[%7.1f s] Burst sent (%d underruns). Listening again.\n', toc(t0), nU);
                L = appendLog(L, tDecided, 'forwarded', slot, hop.routeIn, hop.routeOut, ...
                              hop.nextId, hop.message, nU);

            case 'destination'
                if strcmp(hop.message, deliveredMsg) && toc(t0) < deliveredUntil
                    stats.duplicates = stats.duplicates + 1;
                    fprintf('[%7.1f s] Message %s heard again (route %s): already delivered, duplicate ignored.\n', ...
                            toc(t0), hop.message, hop.routeIn);
                    L = appendLog(L, toc(t0), 'duplicate', slot, hop.routeIn, '', NaN, hop.message, 0);
                    continue;
                end
                deliveredMsg = hop.message;
                deliveredUntil = burstEnd + 3*N*fh.dwell;   % room for the relay's copy
                if isempty(hop.skipped)
                    viaText = '';
                else
                    viaText = sprintf(' Heard directly: SDR(s) %s skipped.', idText(hop.skipped));
                end
                fprintf('[%7.1f s] *** DELIVERED: message %s (slot %d). This node, SDR %d, is the destination.%s ***\n', ...
                        toc(t0), hop.message, slot, opts.myId, viaText);                stats.delivered{end+1} = hop.message;
                L = appendLog(L, toc(t0), 'delivered', slot, hop.routeIn, '', NaN, hop.message, 0);

            case 'notMine'
                stats.ignored = stats.ignored + 1;
                fprintf('[%7.1f s] Heard a burst for SDR %d (hops left %s): not mine, ignored.\n', ...
                        toc(t0), hop.idsIn(1), idText(hop.idsIn));
                L = appendLog(L, toc(t0), 'ignored', slot, hop.routeIn, '', NaN, hop.message, 0);

            case 'unordered'
                stats.ignored = stats.ignored + 1;
                fprintf(['[%7.1f s] Heard route %s, which has no hop order (bitmask / sorted list): ' ...
                         'ignored. Every node needs the new route files.\n'], toc(t0), hop.routeIn);
                L = appendLog(L, toc(t0), 'unordered', slot, hop.routeIn, '', NaN, hop.message, 0);

            otherwise
                stats.ignored = stats.ignored + 1;
                fprintf('[%7.1f s] Heard payload %s with no readable route: ignored.\n', toc(t0), payload);
                L = appendLog(L, toc(t0), 'invalid', slot, '', '', NaN, payload, 0);
        end
    end

    stats.duration = toc(t0);
    stats.eventLog = L;
    stats.myId = opts.myId;
    stats.burstSlots = N;
    stats.dwell = fh.dwell;
    stats.strictNextHop = opts.strictNextHop;

    fprintf('\n--- Repeater SDR %d summary (%.1f s) ---\n', opts.myId, stats.duration);
    fprintf('Originated: %d   Forwarded: %d   Delivered here: %d   Ignored: %d   Duplicates: %d\n', ...
            stats.originated, stats.forwarded, numel(stats.delivered), stats.ignored, stats.duplicates);
    for i = 1:numel(stats.delivered)
        fprintf('  Delivered message: %s\n', stats.delivered{i});
    end
    fprintf('Packets OK: %d   Checksum failed: %d   Header failed: %d   Not part of a burst: %d\n', ...
            stats.packetsOK, stats.checksumFailed, stats.headerFailed, stats.notBurst);
    fprintf('Blocks: %d   with RX overflow: %d   TX underruns: %d   Decode errors: %d\n', ...
            stats.blocks, stats.overflowBlocks, stats.underruns, stats.decodeErrors);
    fprintf('Radios released.\n');
end

% ======================================================================
function frames = buildBurst(cfg, fh, payload, N)
% Every slot of one burst, built before sending so the radio never waits.
    lay = fhPacketLayout(cfg, fh, 12 + numel(payload));
    frames = cell(N, 1);
    for s = 0:N-1
        frames{s+1} = fhBuildSlotFrame(cfg, lay, s, payload);
    end
end

function nUnder = sendBurst(fh, tx, frames)
% Send slots 0 .. N-1, retuning before each one.
    N = numel(frames);
    chans = fhHopSequence(fh, 0:N-1);
    nUnder = 0;
    for s = 1:N
        fhTune(tx, fh, chans(s));
        nUnder = nUnder + double(tx(complex(frames{s})));   % keep it complex (see fhRunLoopback)
    end
end

function t = idText(ids)
    t = strjoin(arrayfun(@num2str, ids(:)', 'UniformOutput', false), ' -> ');
end

function L = emptyLog()
    L = struct('time', zeros(0,1), 'event', {cell(0,1)}, 'slot', zeros(0,1), ...
               'routeIn', {cell(0,1)}, 'routeOut', {cell(0,1)}, 'nextId', zeros(0,1), ...
               'message', {cell(0,1)}, 'underruns', zeros(0,1));
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

function opts = fillDefaults(opts)
    defaults = struct('myId', NaN, 'burstSlots', NaN, 'originate', '', 'strictNextHop', true, ...
                      'duration', Inf, 'framesPerBlock', 4, 'maxFlushFrames', 32, ...
                      'txGuard', 0.2, 'rxLatency', 0);
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(opts, names{k}) || (isempty(opts.(names{k})) && ~strcmp(names{k}, 'originate'))
            opts.(names{k}) = defaults.(names{k});
        end
    end
    opts.originate = char(opts.originate);
    opts.strictNextHop = logical(opts.strictNextHop);
end
