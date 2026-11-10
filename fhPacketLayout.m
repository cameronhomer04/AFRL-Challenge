function lay = fhPacketLayout(cfg, fh, numHexChars)
% FHPACKETLAYOUT  Where packets sit inside one hop slot.
%
%   lay = fhPacketLayout(cfg, fh, numHexChars)
%
%   cfg         - settings from qpskConfig (modem: sample rate, filter, ...)
%   fh          - struct from fhConfig, plus two fields set in runNode_FH:
%                   fh.slotGuard  part of each slot left silent      (default 0.15)
%                   fh.pktGap     silence between packets, as a part
%                                 of one packet's length              (default 0.25)
%   numHexChars - length of the WHOLE message in hex characters, i.e.
%                 12 (hop header) + the user message
%
%   lay - struct:
%       slotSamples   samples in one slot (dwell x sample rate)
%       leadSamples   silence at the start of the slot (LO settles after a retune)
%       trailSamples  silence at the end of the slot (samples still in the
%                     radio's buffer go out before the next retune)
%       pktSamples    samples in one shaped packet
%       gapSamples    silence between packets
%       pktStep       pktSamples + gapSamples
%       pktsPerSlot   packets sent in each slot (at most 256: pktIdx is 8 bits)
%
% Packet k of a slot starts at sample leadSamples + k*pktStep + 1.
% The transmitter and the receiver both call this, so it must be given the
% same cfg, dwell, slotGuard and pktGap on every node.

    if ~isfield(fh, 'slotGuard') || isempty(fh.slotGuard), fh.slotGuard = 0.15; end
    if ~isfield(fh, 'pktGap')    || isempty(fh.pktGap),    fh.pktGap    = 0.25; end

    fs = cfg.sampleRate;
    lay.slotSamples = round(fh.dwell * fs);

    % Guard: the larger of the requested fraction and 5 ms (retune time)
    guard = max(round(fh.slotGuard * lay.slotSamples), ceil(5e-3 * fs));
    lay.leadSamples  = ceil(guard / 2);
    lay.trailSamples = guard - lay.leadSamples;

    % Length of one shaped packet, measured by building a dummy one
    bits = buildPacketBits(repmat('0', 1, numHexChars), cfg);
    w = pulseShapeTx(dqpskModulate(bits), cfg);
    lay.pktSamples = numel(w);

    lay.gapSamples = max(round(fh.pktGap * lay.pktSamples), ...
                         cfg.filterSpan * cfg.samplesPerSymbol);
    lay.pktStep = lay.pktSamples + lay.gapSamples;

    usable = lay.slotSamples - guard;
    lay.pktsPerSlot = min(256, floor((usable + lay.gapSamples) / lay.pktStep));
    if lay.pktsPerSlot < 1
        error('fhPacketLayout:dwell', ['A %d-character packet (%.1f ms) does not fit in a ' ...
              '%.0f ms slot after the guard time. Use a longer dwell or a shorter message.'], ...
              numHexChars, 1e3 * lay.pktSamples / fs, 1e3 * fh.dwell);
    end
end
