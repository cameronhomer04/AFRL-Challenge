%% Run one FREQUENCY-HOPPING SDR node of the DQPSK network
% Same modem as runNode.m (pi/4-DQPSK, qpskConfig), but the node changes
% channel every dwell, following a pseudo-random sequence worked out from a
% shared key. Put this folder on every computer and change only the NODE
% SETTINGS section on each one. The HOPPING SETTINGS must be identical on
% every node, or they hop to different channels.
%
%   role = "tx"   hops and sends packets until stopped
%   role = "rx"   finds the transmitter, follows its hops, decodes its packets
%   role = "both" loopback on ONE radio: transmits and receives on the same
%                 hop sequence and measures the bit error rate per channel.
%                 Cable the radio's TX port to its RX port through 30 dB+
%                 of attenuation: the TX port of txChannel to the RX port
%                 of rxChannel set in qpskConfig (channel 1 = side A,
%                 channel 2 = side B).
%   role = "repeater"  mesh node on ONE radio: listens for hopping bursts and
%                 passes each alert one step along its A* route (fhRunRepeater).
%                 Run it on EVERY node of the chain, each with its own myId.
%                 The node in the A* start square also sets originate = true.
%
% For "tx" + "rx" on two radios, start the TX node first. The RX node finds
% the transmitter within nCh x dwell seconds (printed at start-up).
% For "repeater", start the relays and the destination first, then the
% originator. Each alert travels as one burst of burstSeconds per hop.
%
% THREE-NODE BENCH DEMO (TX -> repeater -> RX, all within range of each other):
%   SDR 1: role "tx" (or "repeater" with originate = true)   (sends the alert)
%   SDR 2: role "repeater"                                   (relays it)
%   SDR 3: role "rx" (live window) or "repeater", strictNextHop = true
% Start SDR 2 and SDR 3 first, then SDR 1. Every sender removes its own ID
% from the front of the route (SDR 1 sends route 2 -> 3).
% With strictNextHop = true, SDR 3 ignores SDR 1's packets (the route starts
% with SDR 2) and delivers only after SDR 2 has relayed it. Set it false to
% show the normal behaviour: SDR 3 takes the message as soon as it hears it.
% A "tx" node keeps sending after its first burst-length of slots; a
% repeater relays it once (slots 0 .. burstSlots-1) and ignores the rest.
% Restart the TX node to raise the alert again.
%
% Every packet is  [ preamble | length | 12-hex-char hop header | message | CRC-16 ]
% The hop header (slot number, packet number, CRC-8) lets a receiver join
% the hop sequence at any time. The CRC-16 (payloadChecksum) covers the
% whole payload; every node needs the CRC-16 versions of payloadChecksum.m
% and qpskConfig.m, or no packet will pass.
%
% Files needed in the same folder:
%   this script, fhRunTransmitter, fhRunReceiverLoop, fhRunLoopback,
%   fhRunRepeater, fhNextHop,
%   fhPacketLayout, fhBuildSlotFrame, fhHopDisplay, fhAddRoute, fhSplitRoute,
%   hexToSdrList (the version that reads ordered routes),
%   fhConfig, fhHopSequence, fhTune, fhRxFollow, fhHeaderBits, fhReadHeader,
%   fhCrc8, qpskConfig, findSdrRadios, selectSdrRadio, setupSdrNode, releaseSdrNode,
%   createSdrTransmitter, createSdrReceiver, captureBlock, receivePacket,
%   detectPacket, correctFrequencyOffset, dqpskModulate, dqpskDemodulate,
%   pulseShapeTx, buildPacketBits, makePreambleBits, payloadChecksum,
%   hexToBits, bitsToHex, createLiveRxDisplay, updateLiveRxDisplay, spectrumDbfs
%
% RF note: the default band, 910-920 MHz, is inside the 902-928 MHz ISM
% band. Bench-test with the radios cabled through attenuators (30 dB+) and
% check the rules for your band before transmitting over the air.

clear; clc;

%% ---------------- NODE SETTINGS ----------------
role = "both";                     % "tx", "rx", "both" (one-radio loopback) or "repeater"
radioChoice = 'any';               % 'any', 'B210' or 'X310'
x310Addresses = {};                % X310 IPs to probe if the search misses one, e.g. {'192.168.10.2'}

% TX / BOTH / REPEATER originator: message(s) to send, up to 243 hex characters
% each (12 go to the header). The repeater sends the first one only.
% List several to take turns, e.g. ["DEAD", "BEEF"].
hexMessages     = "1100A0C";
messageInterval = 5;               % seconds on each message when several are listed

% A* ROUTING NUMBER: put the route from the A* script in front of every message.
% In astar_demo.m add  fhSaveRoute(sdrHex, sdrList, numSdrs);  after routeToSdrMask,
% run it, and copy route_hex.mat next to this file.
useAstarRoute = true;
routeFile     = "route_hex.mat";   % saved by fhSaveRoute
routeHex      = "";                % or type a routing number here, e.g. "010D" (overrides routeFile)
myId          = 1;                 % this node's SDR ID in the A* SDR bank (every role).
                                   % TX: must be the first SDR on the route.

% DEMO SWITCH (RX and REPEATER): next-hop filter
strictNextHop = true;              % true  = DEMO: accept a message only when myId is FIRST in
                                   %         its route, i.e. after the node before this one has
                                   %         relayed it. Use this when the nodes sit too close
                                   %         together for the repeater to be needed.
                                   % false = NORMAL: accept any message whose route lists myId,
                                   %         even if it was heard straight from the sender
                                   %         (relays in front of this node are skipped).

% REPEATER: every node of the chain runs role "repeater" with its own myId.
originate = false;                 % true on the node that raises the alert: it sends
                                   % hexMessages(1) along the route in routeFile once,
                                   % then relays like every other node. Relays need no
                                   % route file: the route arrives in every packet.
txGuard   = 0.2;                   % extra wait (s) after the incoming burst ends before
                                   % sending; raise it if a relay starts while the
                                   % previous node is still on air

runDuration = 30;                  % seconds to run; Inf = until Stop / Ctrl+C
                                   % (relays: Inf, or long enough for the alert to arrive)
showPlots   = true;                % TX: Stop window. RX / BOTH: live receiver window.
                                   % REPEATER: summary figure at the end (no live window).

% RX / BOTH
framesPerBlock = 4;                % frames decoded per pass (4 x 4096 samples = 20 ms)
useBurstMode   = true;             % RX only: gap-free blocks; set false if your MATLAB version rejects it

% RX: finding and keeping the transmitter
acquireMode    = "scan";           % "scan": try the next channel every scanBlocks blocks until a
                                   % packet is heard (found in about channels x scanBlocks
                                   % blocks). "park": wait on one channel (up to 2 x channels
                                   % x dwell, e.g. 9.5 s for 10 ch x 0.5 s).
scanBlocks     = 1;                % blocks on each channel while scanning
lostAfterSlots = 4;                % slots with no good packet before scanning again
rxLatency      = 0;                % s from the radio taking a sample to MATLAB getting it.
                                   % Raise to ~0.03 (B210 on USB) if the summary reports many
                                   % "packets from a channel already left".
% The RX never loads routeFile: it learns the route from the packets it receives.

% BOTH (one-radio loopback): proof that every slot gets the message
printEachSlot     = true;          % one PASS/FAIL line per slot in the Command Window
minPacketsPerSlot = 1;             % packets with the exact message needed for a slot to PASS
saveSlotLog       = true;          % write every slot's metrics (BOTH) or every repeater
                                   % event (REPEATER) to a CSV file at the end

% BOTH: drop channels that keep failing (adaptive hopping)
adaptiveHopping = true;
surveyVisits    = 2;               % visits to every channel before judging it
minPassRate     = 0.5;             % drop channels passing less than this part of their slots
minPacketRate   = 0.5;             % ... or delivering less than this part of their packets
minChannels     = 25;              % never hop over fewer channels than this. Bench only: over
                                   % the air in 902-928 MHz, FCC 15.247 needs 50+ channels at
                                   % this channel width, so plan spares (nCh > 50) and set 50.

%% ---------------- HOPPING SETTINGS (identical on every node) ----------------
fc        = 915e6;                 % centre of the hopping band (Hz)
nCh       = 10;                    % number of channels (even is best)
chSpacing = 1e6;                 % channel spacing (Hz); the modem uses about 135 kHz
dwell     = .5;                  % time on each channel (s); 0.1 s or more
hopKey    = 20261107;              % shared hop key, whole number below 2^32
slotGuard = 0.15;                  % part of each slot kept silent for the retune
pktGap    = 0.25;                  % silence between packets, part of one packet's length
excludeChannels = [];              % channels never used, e.g. [7 18 33] from a loopback
                                   % run's summary. MUST be the same on every node.
burstSeconds = "auto";             % REPEATER: length of every burst (s). "auto" = up to the
                                   % slot where the listening channel comes round again,
                                   % + 1 slot + 0.5 s to decode, so a node that misses
                                   % slot 0 gets a second chance (key 20261107, 10 ch x
                                   % 0.2 s -> 4.0 s). MUST be the same on every node.

%% ---------------- Modem and hopping configuration ----------------
cfg = qpskConfig();
cfg.centerFrequency = fc;          % starting LO; fhTune moves it every hop

occupied = cfg.symbolRate * (1 + cfg.rolloff);
if occupied > chSpacing
    error('The modem occupies %.0f kHz but channels are only %.0f kHz apart.', ...
          occupied/1e3, chSpacing/1e3);
end

radios = findSdrRadios(x310Addresses);
fprintf("Radios found:\n");
for k = 1:numel(radios)
    fprintf("  %d) %s  %s\n", k, radios(k).Platform, radios(k).Address);
end
nodeRadio = selectSdrRadio(radios, radioChoice);
% "both" on two radios attached to this computer (TX first, RX second):
%   nodeRadio = [selectSdrRadio(radios, 'B210'), selectSdrRadio(radios, 'X310')];

fh = fhConfig(fc, nCh, 'Bandwidth', nCh*chSpacing, 'Dwell', dwell, 'Key', hopKey, ...
              'Mode', 'lo', 'TxRadio', nodeRadio(1).Platform, 'RxRadio', nodeRadio(end).Platform);
fh.slotGuard = slotGuard;          % used by fhPacketLayout on both sides
fh.pktGap    = pktGap;
fh.allowed   = setdiff(1:nCh, excludeChannels);   % fhHopSequence hops over these only
if numel(fh.allowed) < 2
    error('excludeChannels leaves fewer than 2 channels to hop over.');
end
% Only the band plan, key, dwell and mode of fh are used here. Sample rate,
% symbol rate and samples per symbol come from qpskConfig (cfg).

fprintf("\nBand %.3f - %.3f MHz: %d channels x %.0f kHz, dwell %.0f ms, key %d\n", ...
        fh.edges/1e6, fh.nCh, fh.spacing/1e3, 1e3*fh.dwell, fh.key);
if ~isempty(excludeChannels)
    fprintf("Excluded channels: %s (hopping over %d)\n", mat2str(sort(excludeChannels)), numel(fh.allowed));
end
fprintf("Modem: %.0f ksymbol/s, %.0f kHz occupied, %.3f MSample/s\n", ...
        cfg.symbolRate/1e3, occupied/1e3, cfg.sampleRate/1e6);
fprintf("First 10 hops: channels %s\n", mat2str(fhHopSequence(fh, 0:9)));
if lower(string(role)) == "rx"
    if lower(string(acquireMode)) == "scan"
        fprintf("The receiver scans the %d channels and should lock within about %d blocks once the transmitter is on air.\n", ...
                numel(fh.allowed), numel(fh.allowed) * scanBlocks);
    else
        fprintf("The receiver, parked on one channel, finds the transmitter within %.1f s (up to %.1f s if it missed slot 0).\n", ...
                numel(fh.allowed) * fh.dwell, (2*numel(fh.allowed) - 1) * fh.dwell);
    end
end

% Burst length for the repeater: every burst is slots 0 .. burstSlots-1.
% Listeners park on the channel of slot 0. The hop order changes every pass
% through the channels, so that channel comes round again anywhere from
% slot n+1 to slot 2n-1 (n = channels in use); the burst must reach it.
parkSeq = fhHopSequence(fh, 0 : 2*numel(fh.allowed) - 1);
secondVisit = find(parkSeq(2:end) == parkSeq(1), 1);     % slot number of the 2nd visit
if (isstring(burstSeconds) || ischar(burstSeconds)) && strcmpi(burstSeconds, "auto")
    burstSeconds = (secondVisit + 1) * fh.dwell + 0.5;
end
fh.burstSlots = ceil(burstSeconds / fh.dwell - 1e-9);
if lower(string(role)) == "repeater"
    fprintf("Repeater bursts: %d slots = %.1f s per hop (listening channel %d is used in slots 0 and %d).\n", ...
            fh.burstSlots, fh.burstSlots * fh.dwell, parkSeq(1), secondVisit);
end

%% ---------------- A* routing number ----------------
role = lower(string(role));
routeMode = false;
if role == "repeater"
    if ~useAstarRoute
        error('The "repeater" role needs useAstarRoute = true: it forwards along the route in each packet.');
    end
    if isempty(myId) || isnan(myId)
        error('Set myId to this radio''s SDR ID for the "repeater" role.');
    end
end
% Only a sender loads the route file. A receiver ("rx") and a relay that does
% not originate learn the route from the packets they hear.
loadRoute = useAstarRoute && role ~= "rx" && ~(role == "repeater" && ~originate);
if useAstarRoute && ~loadRoute
    if role == "rx"
        fprintf("\nRX SDR %d: no route file loaded; the route is read from each packet.\n", myId);
    else
        fprintf("\nRepeater SDR %d: relays only (originate = false), no route file needed.\n", myId);
    end
    routeMode = true;
end
if loadRoute
    if strlength(string(routeHex)) == 0
        if ~exist(routeFile, "file")
            error(['No routing number: %s not found. Run astar_demo.m with ' ...
                   'fhSaveRoute(sdrHex, sdrList, numSdrs) added, copy the file here, ' ...
                   'or type one into routeHex.'], routeFile);
        end
        saved = load(routeFile, "routeHex");
        routeHex = saved.routeHex;
        fprintf("\nA* routing number loaded from %s\n", routeFile);
    end
    routeHex = upper(char(routeHex));
    try
        [routeSdrs, routeFormat] = hexToSdrList(routeHex);
    catch err
        error(['Could not read routing number %s (%s).\nUse the new hexToSdrList.m: the ' ...
               'older copies do not read ordered (''2'') routes.'], ...
              routeHex, err.message);
    end
    fprintf("A* route: %s (%s, %d hex digits) -> SDRs %s\n", routeHex, routeFormat, ...
            numel(routeHex), mat2str(routeSdrs(:)'));
    if role ~= "tx"
        if any(routeSdrs == myId), onText = "IS"; else, onText = "is NOT"; end
        fprintf("This node (SDR %d) %s on the route.\n", myId, onText);
    end
    if role == "repeater"                         % the originator must be first on the route
        if ~strcmp(routeFormat, 'ordered')
            error(['Route %s is a %s route, which has no hop order. Re-run the A* script ' ...
                   '(routeToSdrMask now saves an ordered route) and copy route_hex.mat here.'], ...
                  routeHex, routeFormat);
        end
        fprintf("Hop order: %s\n", strjoin(arrayfun(@num2str, routeSdrs(:)', ...
                'UniformOutput', false), ' -> '));
        if routeSdrs(1) ~= myId
            warning(['The route starts at SDR %d but myId is %d: the alert will NOT be sent. ' ...
                     'Use this route on SDR %d, or fix myId.'], routeSdrs(1), myId, routeSdrs(1));
        end
        allMsgs = cellstr(hexMessages);
        if numel(allMsgs) > 1
            fprintf("Repeater: only the first message is sent (%s).\n", allMsgs{1});
        end
        hexMessages = allMsgs(1);
    end
    if role == "tx"                               % the TX node must be first on the route
        if isempty(myId) || isnan(myId)
            error('Set myId to this radio''s SDR ID: the "tx" role removes it from the route.');
        end
        if strcmp(routeFormat, 'ordered')
            fprintf("Hop order: %s\n", strjoin(arrayfun(@num2str, routeSdrs(:)', ...
                    'UniformOutput', false), ' -> '));
            if routeSdrs(1) ~= myId
                error(['The route starts at SDR %d but myId is %d. Use this route on SDR %d, ' ...
                       'or fix myId.'], routeSdrs(1), myId, routeSdrs(1));
            end
            if numel(routeSdrs) < 2
                error('The route lists only this node (SDR %d): there is nobody to send to.', myId);
            end
        else
            warning(['Route %s is a %s route (no hop order), so SDR %d cannot be removed from ' ...
                     'it. It is sent unchanged; repeaters will ignore it.'], ...
                    routeHex, routeFormat, myId);
        end
    end
    if role ~= "rx"                               % sent as [ route length | route | message ]
        msgs = cellstr(hexMessages);
        for k = 1:numel(msgs)
            msgs{k} = fhAddRoute(routeHex, msgs{k});
            % TX: remove my own ID from the front of the route, the same rule
            % a repeater originator uses (fhNextHop), so the next node acts on it.
            if role == "tx" && strcmp(routeFormat, 'ordered')
                hop = fhNextHop(msgs{k}, myId, true);
                msgs{k} = hop.payloadOut;
                if k == 1
                    fprintf("TX sends route %s (SDR %d removed): next hop SDR %d.\n", ...
                            hop.routeOut, myId, hop.nextId);
                end
            end
            if numel(msgs{k}) > cfg.maxHexChars - 12
                error(['Route (%d hex digits) + its 2-digit length + message %d is %d hex ' ...
                       'characters; at most %d fit in a packet. Shorten the message or use a ' ...
                       'smaller SDR bank.'], numel(routeHex), k, numel(msgs{k}), cfg.maxHexChars - 12);
            end
        end
        hexMessages = msgs;
        fprintf("Each payload: %s\n", msgs{1});
    end
    routeMode = true;
end

if role == "rx" || role == "repeater"
    if strictNextHop
        fprintf("Next-hop filter: STRICT (demo) - SDR %d acts only when it is first in the route.\n", myId);
    else
        fprintf("Next-hop filter: OFF - SDR %d acts on any message whose route lists it.\n", myId);
    end
end

%% ---------------- Set up and run ----------------
if role == "rx" && useBurstMode         % "both" streams TX and RX together: no burst mode
    rxBurstFrames = framesPerBlock;
else
    rxBurstFrames = 0;
end

sdr = setupSdrNode(cfg, nodeRadio, role, rxBurstFrames);
fprintf("\nRole: %s (frequency hopping)\n", upper(sdr.role));

switch sdr.role
    case "tx"
        fprintf("  TX on %s %s\n", sdr.txRadio.Platform, sdr.txRadio.Address);
        txOpts = struct("duration", runDuration, "messageInterval", messageInterval, ...
                        "showDisplay", showPlots);
        txStats = fhRunTransmitter(cfg, fh, sdr.tx, hexMessages, txOpts);

    case "rx"
        fprintf("  RX on %s %s\n", sdr.rxRadio.Platform, sdr.rxRadio.Address);
        rxOpts = struct("framesPerBlock", framesPerBlock, ...
                        "maxFlushFrames", 32 * ~useBurstMode, ...
                        "duration", runDuration, "showDisplay", showPlots, ...
                        "routeMode", routeMode, "myId", myId, ...
                        "strictNextHop", strictNextHop, ...
                        "acquire", char(acquireMode), "scanBlocks", scanBlocks, ...
                        "lostAfterSlots", lostAfterSlots, "rxLatency", rxLatency);
        rxStats = fhRunReceiverLoop(cfg, fh, sdr.rx, rxOpts);

    case "both"
        fprintf("  TX on %s %s, RX on %s %s\n", sdr.txRadio.Platform, sdr.txRadio.Address, ...
                sdr.rxRadio.Platform, sdr.rxRadio.Address);
        lbOpts = struct("duration", runDuration, "messageInterval", messageInterval, ...
                        "showDisplay", showPlots, "showHopDisplay", showPlots, ...
                        "framesPerBlock", framesPerBlock, "printEachSlot", printEachSlot, ...
                        "minPacketsPerSlot", minPacketsPerSlot, "adaptive", adaptiveHopping, ...
                        "surveyVisits", surveyVisits, "minPassRate", minPassRate, ...
                        "minPacketRate", minPacketRate, ...
                        "minChannels", minChannels, "routeMode", routeMode, "myId", myId);
        lbStats = fhRunLoopback(cfg, fh, sdr, hexMessages, lbOpts);

        % Every slot's metrics, one row per slot (open in Excel or MATLAB)
        slotTable = struct2table(lbStats.slotLog);
        if saveSlotLog && height(slotTable) > 0
            logFile = sprintf("fh_slot_log_%s.csv", datestr(now, "yyyymmdd_HHMMSS"));
            writetable(slotTable, logFile);
            fprintf("Slot-by-slot metrics saved to %s (also in the variable slotTable).\n", logFile);
        end

    case "repeater"
        fprintf("  TX on %s %s, RX on %s %s, SDR %d\n", sdr.txRadio.Platform, sdr.txRadio.Address, ...
                sdr.rxRadio.Platform, sdr.rxRadio.Address, myId);
        originatePayload = '';
        if originate
            originatePayload = hexMessages{1};    % [ route length | route | message ]
        end
        rpOpts = struct("myId", myId, "burstSlots", fh.burstSlots, ...
                        "originate", originatePayload, "strictNextHop", strictNextHop, ...
                        "duration", runDuration, ...
                        "framesPerBlock", framesPerBlock, "txGuard", txGuard);
        rpStats = fhRunRepeater(cfg, fh, sdr, rpOpts);
        if showPlots
            fhRepeaterSummary(rpStats, fh);        % redraw later with fhRepeaterSummary(rpStats, fh)
        end

        % One row per event: originated, forwarded, delivered, duplicate, ignored
        eventTable = struct2table(rpStats.eventLog);
        if saveSlotLog && height(eventTable) > 0
            logFile = sprintf("fh_repeater_log_SDR%d_%s.csv", myId, datestr(now, "yyyymmdd_HHMMSS"));
            writetable(eventTable, logFile);
            fprintf("Repeater events saved to %s (also in the variable eventTable).\n", logFile);
        end

    otherwise
        releaseSdrNode(sdr);
        error('runNode_FH supports role "tx", "rx", "both" or "repeater".');
end
