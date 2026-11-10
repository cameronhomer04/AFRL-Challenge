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
%
% For "tx" + "rx" on two radios, start the TX node first. The RX node finds
% the transmitter within nCh x dwell seconds (printed at start-up).
%
% Every packet is  [ preamble | length | 12-hex-char hop header | message | checksum ]
% The hop header (slot number, packet number, CRC-8) lets a receiver join
% the hop sequence at any time.
%
% Files needed in the same folder:
%   this script, fhRunTransmitter, fhRunReceiverLoop, fhRunLoopback,
%   fhPacketLayout, fhBuildSlotFrame, fhHopDisplay, fhAddRoute, fhSplitRoute,
%   hexToSdrList (the version from the project's claude/ folder),
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
role = "both";                     % "tx", "rx" or "both" (one-radio loopback)
radioChoice = 'any';               % 'any', 'B210' or 'X310'
x310Addresses = {};                % X310 IPs to probe if the search misses one, e.g. {'192.168.10.2'}

% TX / BOTH: message(s) to send, up to 243 hex characters each (12 go to the header).
% List several to take turns, e.g. ["DEAD", "BEEF"].
hexMessages     = "1100A0C";
messageInterval = 5;               % seconds on each message when several are listed

% A* ROUTING NUMBER: put the route from the A* script in front of every message.
% In astar_demo.m add  fhSaveRoute(sdrHex, sdrList, numSdrs);  after routeToSdrMask,
% run it, and copy route_hex.mat next to this file.
useAstarRoute = true;
routeFile     = "route_hex.mat";   % saved by fhSaveRoute
routeHex      = "";                % or type a routing number here, e.g. "010D" (overrides routeFile)
myId          = 1;                 % RX / BOTH: this node's SDR ID in the A* SDR bank

runDuration = 30;                  % seconds to run; Inf = until Stop / Ctrl+C
showPlots   = true;                % TX: Stop window. RX / BOTH: live receiver window.

% RX / BOTH
framesPerBlock = 4;                % frames decoded per pass (4 x 4096 samples = 20 ms)
useBurstMode   = true;             % RX only: gap-free blocks; set false if your MATLAB version rejects it

% BOTH (one-radio loopback): proof that every slot gets the message
printEachSlot     = true;          % one PASS/FAIL line per slot in the Command Window
minPacketsPerSlot = 1;             % packets with the exact message needed for a slot to PASS
saveSlotLog       = true;          % write every slot's metrics to a CSV file at the end

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
fprintf("A receiver finds the transmitter within %.1f s (one pass through every channel).\n", ...
        numel(fh.allowed) * fh.dwell);

%% ---------------- A* routing number ----------------
role = lower(string(role));
routeMode = false;
if useAstarRoute
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
        error(['Could not read routing number %s (%s).\nUse the hexToSdrList.m from the ' ...
               'project''s claude/ folder: the older copy only reads bitmask routes.'], ...
              routeHex, err.message);
    end
    fprintf("A* route: %s (%s, %d hex digits) -> SDRs %s\n", routeHex, routeFormat, ...
            numel(routeHex), mat2str(routeSdrs(:)'));
    if role ~= "tx"
        if any(routeSdrs == myId), onText = "IS"; else, onText = "is NOT"; end
        fprintf("This node (SDR %d) %s on the route.\n", myId, onText);
    end
    if role ~= "rx"                               % sent as [ route length | route | message ]
        msgs = cellstr(hexMessages);
        for k = 1:numel(msgs)
            msgs{k} = fhAddRoute(routeHex, msgs{k});
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
                        "routeMode", routeMode, "myId", myId);
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

    otherwise
        releaseSdrNode(sdr);
        error('runNode_FH supports role "tx", "rx" or "both".');
end
